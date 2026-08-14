require 'rails_helper'

describe Campaigns::ReconcileMetaAnalyticsJob do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:whatsapp_inbox) { whatsapp_channel.inbox }

  describe '#perform' do
    it 'reconciles recent one-off WhatsApp campaigns' do
      recent_campaign = create(:campaign, inbox: whatsapp_inbox, account: account, campaign_type: :one_off)

      old_campaign = create(:campaign, inbox: whatsapp_inbox, account: account, campaign_type: :one_off)
      old_campaign.update!(created_at: 30.days.ago)

      other_channel_inbox = create(:inbox, account: account)
      other_channel_campaign = create(:campaign, inbox: other_channel_inbox, account: account, campaign_type: :one_off)

      processed_campaign_ids = []
      allow(Campaigns::MetaAnalyticsReconciler).to receive(:new) do |campaign:|
        processed_campaign_ids << campaign.id
        instance_double(Campaigns::MetaAnalyticsReconciler, perform: nil)
      end

      described_class.perform_now

      expect(processed_campaign_ids).to include(recent_campaign.id)
      expect(processed_campaign_ids).not_to include(old_campaign.id, other_channel_campaign.id)
    end
  end
end
