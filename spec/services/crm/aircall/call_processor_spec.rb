require 'rails_helper'

describe Crm::Aircall::CallProcessor do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { whatsapp_channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+529843128950') }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  def call_data(overrides = {})
    {
      'id' => 3_970_535_284,
      'raw_digits' => '+52 984 312 8950',
      'direction' => 'inbound',
      'started_at' => 10.minutes.ago.to_i,
      'answered_at' => 9.minutes.ago.to_i,
      'ended_at' => 5.minutes.ago.to_i,
      'duration' => 240
    }.merge(overrides)
  end

  it 'matches the contact even when raw_digits comes formatted with spaces (Aircall REST history shape)' do
    described_class.new(account: account, call_data: call_data).perform

    call = Call.find_by(provider: :aircall, provider_call_id: '3970535284')
    expect(call).to be_present
    expect(call.contact).to eq(contact)
    expect(call.conversation).to eq(conversation)
  end

  it 'dates the message with the real call date, not the time it was processed (backfill)' do
    a_month_ago = 1.month.ago.to_i

    described_class.new(account: account, call_data: call_data('started_at' => a_month_ago, 'answered_at' => a_month_ago)).perform

    message = conversation.messages.find_by(content_type: :voice_call)
    expect(message.created_at).to be_within(1.second).of(Time.zone.at(a_month_ago))
  end

  context 'when the conversation already has more recent activity than the backfilled call' do
    before do
      create(:message, conversation: conversation, message_type: :outgoing)
      conversation.update!(waiting_since: nil)
    end

    it 'does not rewind conversation.last_activity_at' do
      recent_last_activity_at = conversation.last_activity_at

      described_class.new(account: account, call_data: call_data('started_at' => 1.month.ago.to_i, 'answered_at' => 1.month.ago.to_i)).perform

      expect(conversation.reload.last_activity_at).to be_within(1.second).of(recent_last_activity_at)
    end

    it 'does not resurrect waiting_since from a backdated incoming call' do
      described_class.new(account: account, call_data: call_data('started_at' => 1.month.ago.to_i, 'answered_at' => nil)).perform

      expect(conversation.reload.waiting_since).to be_nil
    end
  end

  it 'does update conversation.last_activity_at when the call is genuinely the most recent activity' do
    conversation.update!(last_activity_at: 2.months.ago)

    described_class.new(account: account, call_data: call_data).perform

    message = conversation.messages.find_by(content_type: :voice_call)
    expect(conversation.reload.last_activity_at).to be_within(1.second).of(message.created_at)
  end
end
