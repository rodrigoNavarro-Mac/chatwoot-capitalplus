require 'rails_helper'

describe Campaigns::MetaAnalyticsReconciler do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:campaign) do
    create(:campaign, inbox: whatsapp_inbox, account: account,
                      template_params: { 'name' => 'test_no_params_template', 'language' => 'en' })
  end
  let(:analytics_client) { instance_double(Whatsapp::TemplateAnalyticsClient) }

  before do
    allow(Whatsapp::TemplateAnalyticsClient).to receive(:new).and_return(analytics_client)
    CampaignMessageDelivery.create!(
      account: account, campaign: campaign, audience_type: 'csv', phone_number: '+15550001111',
      source_id: 'wamid.1', sent_at: 1.day.ago, delivered_at: 1.day.ago
    )
  end

  describe '#perform' do
    it 'returns nil without calling Meta when the template cannot be resolved from message_templates' do
      campaign.update!(template_params: { 'name' => 'unknown_template', 'language' => 'en' })

      expect(analytics_client).not_to receive(:fetch)
      expect(described_class.new(campaign: campaign).perform).to be_nil
    end

    it 'reports no discrepancy when Meta and Chatwoot roughly agree' do
      allow(analytics_client).to receive(:fetch).and_return(
        '9876543210987654' => { sent: 1, delivered: 1, read: 0, clicked: 0 }
      )

      expect(described_class.new(campaign: campaign).perform).to eq([])
    end

    it 'flags a discrepancy when Meta reports significantly more delivered than Chatwoot recorded' do
      allow(analytics_client).to receive(:fetch).and_return(
        '9876543210987654' => { sent: 10, delivered: 10, read: 8, clicked: 0 }
      )

      discrepancies = described_class.new(campaign: campaign).perform

      delivered_gap = discrepancies.find { |d| d[:metric] == :delivered }
      expect(delivered_gap).to include(meta: 10, chatwoot: 1)
    end

    it 'rescues and logs when the analytics client raises' do
      allow(analytics_client).to receive(:fetch).and_raise('boom')
      allow(Rails.logger).to receive(:error)

      expect(described_class.new(campaign: campaign).perform).to be_nil
      expect(Rails.logger).to have_received(:error).with(/failed to reconcile - boom/)
    end
  end
end
