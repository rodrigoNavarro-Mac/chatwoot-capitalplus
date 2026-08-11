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
end
