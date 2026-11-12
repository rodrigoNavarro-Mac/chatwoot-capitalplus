require 'rails_helper'

describe Campaigns::MessageDeliveryRecorder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:campaign) { create(:campaign, account: account, inbox: inbox) }
  let(:contact) { create(:contact, :with_phone_number, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing) }

  describe '#record_labels_delivery' do
    it 'stamps the wamid on the chat message and clears a stale send error' do
      message.update!(external_error: 'Message not sent because the WhatsApp 24-hour customer service window is closed')

      described_class.new(campaign: campaign).record_labels_delivery(contact: contact, message: message,
                                                                     wa_message_id: 'wamid.camp1', send_error: nil)

      expect(message.reload.source_id).to eq('wamid.camp1')
      expect(message.external_error).to be_nil
      expect(campaign.campaign_message_deliveries.last).to have_attributes(status: 'sent', source_id: 'wamid.camp1')
    end

    it 'keeps the message untouched when the send did not reach Meta' do
      described_class.new(campaign: campaign).record_labels_delivery(contact: contact, message: message,
                                                                     wa_message_id: nil, send_error: 'boom')

      expect(message.reload.source_id).to be_nil
      expect(campaign.campaign_message_deliveries.last).to have_attributes(status: 'failed', failed_reason: 'boom')
    end
  end
end
