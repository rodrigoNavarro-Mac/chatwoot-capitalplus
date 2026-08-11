require 'rails_helper'

describe Crm::Aircall::InboundWebhookService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { whatsapp_channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+529843128950') }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  def call_ended_payload(overrides = {})
    {
      'event' => 'call.ended',
      'data' => {
        'id' => 999_001,
        'raw_digits' => '+529843128950',
        'direction' => 'inbound',
        'started_at' => 10.minutes.ago.to_i,
        'answered_at' => 9.minutes.ago.to_i,
        'ended_at' => 5.minutes.ago.to_i,
        'duration' => 240
      }.merge(overrides)
    }
  end

  it 'creates a Call in the contact\'s earliest conversation' do
    described_class.new(account, call_ended_payload).perform

    call = Call.find_by(provider: :aircall, provider_call_id: '999001')
    expect(call).to be_present
    expect(call.conversation).to eq(conversation)
    expect(call.contact).to eq(contact)
    expect(call.status).to eq('completed')
    expect(call.duration_seconds).to eq(240)
  end

  it 'creates an incoming voice_call Message linked back to the Call' do
    described_class.new(account, call_ended_payload).perform

    call = Call.find_by(provider: :aircall, provider_call_id: '999001')
    message = conversation.messages.last
    expect(message.content_type).to eq('voice_call')
    expect(message.message_type).to eq('incoming')
    expect(call.message_id).to eq(message.id)
  end

  it 'marks the call as no_answer when there is no answered_at' do
    described_class.new(account, call_ended_payload('answered_at' => nil)).perform

    call = Call.find_by(provider: :aircall, provider_call_id: '999001')
    expect(call.status).to eq('no_answer')
  end

  it 'creates an outgoing message for an outbound call, sent by the resolved agent' do
    agent = create(:user, email: 'eunice@capitalplus.mx')
    create(:account_user, account: account, user: agent)

    described_class.new(account, call_ended_payload(
                                   'direction' => 'outbound', 'user' => { 'email' => 'eunice@capitalplus.mx' }
                                 )).perform

    call = Call.find_by(provider: :aircall, provider_call_id: '999001')
    expect(call.direction).to eq('outgoing')
    expect(call.accepted_by_agent).to eq(agent)
    expect(conversation.messages.last.message_type).to eq('outgoing')
  end

  it 'is idempotent for the same Aircall call id' do
    2.times { described_class.new(account, call_ended_payload).perform }

    expect(Call.where(provider: :aircall, provider_call_id: '999001').count).to eq(1)
    expect(conversation.messages.where(content_type: :voice_call).count).to eq(1)
  end

  it 'ignores events other than call.ended' do
    described_class.new(account, call_ended_payload.merge('event' => 'call.created')).perform

    expect(Call.where(provider: :aircall)).to be_empty
  end

  it 'ignores anonymous calls' do
    described_class.new(account, call_ended_payload('raw_digits' => 'anonymous')).perform

    expect(Call.where(provider: :aircall)).to be_empty
  end

  it 'ignores calls from numbers with no matching contact' do
    described_class.new(account, call_ended_payload('raw_digits' => '+15550001111')).perform

    expect(Call.where(provider: :aircall)).to be_empty
  end

  it 'ignores calls for a contact with no existing conversation' do
    lonely_contact = create(:contact, account: account, phone_number: '+525500000000')

    described_class.new(account, call_ended_payload('raw_digits' => '+525500000000')).perform

    expect(Call.where(provider: :aircall)).to be_empty
    expect(lonely_contact.reload.conversations).to be_empty
  end
end
