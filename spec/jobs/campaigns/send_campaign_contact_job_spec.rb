require 'rails_helper'

RSpec.describe Campaigns::SendCampaignContactJob do
  let(:account) { create(:account) }
  let!(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let!(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:contact) { create(:contact, :with_phone_number, account: account) }

  context 'when the campaign is processing' do
    let(:campaign) { create(:campaign, inbox: whatsapp_inbox, account: account, campaign_status: :processing) }

    it 'delegates to the service for a labeled contact' do
      service = instance_double(Whatsapp::OneoffCampaignService)
      allow(Whatsapp::OneoffCampaignService).to receive(:new).with(campaign: campaign).and_return(service)
      expect(service).to receive(:send_to_contact).with(contact)

      described_class.perform_now(campaign.id, contact.id)
    end

    it 'delegates to the service for a CSV contact' do
      contact_data = { 'phone_number' => '+15550001111', 'name' => 'Jane' }
      service = instance_double(Whatsapp::OneoffCampaignService)
      allow(Whatsapp::OneoffCampaignService).to receive(:new).with(campaign: campaign).and_return(service)
      expect(service).to receive(:send_to_csv_contact).with(contact_data)

      described_class.perform_now(campaign.id, nil, contact_data)
    end
  end

  # Jobs already sitting in Sidekiq's scheduled set when a campaign is paused (or that
  # somehow survive past completion) must not send anything and must not leave any trace
  # behind — no CampaignMessageDelivery row, since campaign_status is the source of truth.
  %i[active completed paused].each do |status|
    context "when the campaign is #{status}" do
      let(:campaign) { create(:campaign, inbox: whatsapp_inbox, account: account, campaign_status: status) }

      it 'does not call the service or create a delivery' do
        expect(Whatsapp::OneoffCampaignService).not_to receive(:new)

        expect { described_class.perform_now(campaign.id, contact.id) }
          .not_to change(CampaignMessageDelivery, :count)
      end
    end
  end

  context 'when the campaign no longer exists' do
    it 'does nothing' do
      expect(Whatsapp::OneoffCampaignService).not_to receive(:new)

      described_class.perform_now(-1, contact.id)
    end
  end
end
