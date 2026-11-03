require 'rails_helper'

RSpec.describe Campaigns::SendCampaignContactJob do
  let(:account) { create(:account) }
  let!(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let!(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:contact) { create(:contact, :with_phone_number, account: account) }

  # Whatsapp::OneoffCampaignService#perform marks the campaign `completed!` synchronously,
  # right after scheduling every delayed job — long before those jobs actually run. So
  # `completed` (and `active`, `processing`) must still deliver; only an explicit `paused`
  # should stop a job that was already sitting in Sidekiq's scheduled set.
  %i[active processing completed].each do |status|
    context "when the campaign is #{status}" do
      let(:campaign) { create(:campaign, inbox: whatsapp_inbox, account: account, campaign_status: status) }

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
  end

  # Jobs already sitting in Sidekiq's scheduled set when a campaign is paused must not send
  # anything and must not leave any trace behind — no CampaignMessageDelivery row, since
  # campaign_status is the source of truth.
  context 'when the campaign is paused' do
    let(:campaign) { create(:campaign, inbox: whatsapp_inbox, account: account, campaign_status: :paused) }

    it 'does not call the service or create a delivery' do
      expect(Whatsapp::OneoffCampaignService).not_to receive(:new)

      expect { described_class.perform_now(campaign.id, contact.id) }
        .not_to change(CampaignMessageDelivery, :count)
    end
  end

  context 'when the number quality dropped to RED' do
    let(:campaign) { create(:campaign, inbox: whatsapp_inbox, account: account, campaign_status: :completed) }

    before do
      whatsapp_channel.update_columns(phone_number_health: { 'quality_rating' => 'RED', 'status' => 'CONNECTED' }) # rubocop:disable Rails/SkipsModelValidations
    end

    it 'auto-pauses the campaign instead of sending' do
      expect(Whatsapp::OneoffCampaignService).not_to receive(:new)

      described_class.perform_now(campaign.id, nil, { 'phone_number' => '+525511112222' })

      expect(campaign.reload).to be_paused
    end
  end

  context 'when the phone opted out' do
    let(:campaign) { create(:campaign, inbox: whatsapp_inbox, account: account, campaign_status: :completed) }
    let(:opt_out_key) { format(Redis::RedisKeys::WA_OPTED_OUT_PHONES, account_id: account.id) }

    after { Redis::Alfred.delete(opt_out_key) }

    it 'skips the CSV contact' do
      Campaigns::RecipientEligibility.opt_out!(account.id, '+525511112222')
      service = instance_double(Whatsapp::OneoffCampaignService)
      allow(Whatsapp::OneoffCampaignService).to receive(:new).and_return(service)
      expect(service).not_to receive(:send_to_csv_contact)

      described_class.perform_now(campaign.id, nil, { 'phone_number' => '+525511112222' })
    end
  end

  context 'when the campaign no longer exists' do
    it 'does nothing' do
      expect(Whatsapp::OneoffCampaignService).not_to receive(:new)

      described_class.perform_now(-1, contact.id)
    end
  end
end
