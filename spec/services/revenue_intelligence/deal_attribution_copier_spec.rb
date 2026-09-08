require 'rails_helper'

describe RevenueIntelligence::DealAttributionCopier do
  let(:account) { create(:account) }
  let(:lead) do
    account.revenue_leads.create!(zoho_lead_id: 'lead-1', campaign_id: 'camp-1', campaign_name: 'Campaña Q1',
                                  adset_name: 'Adset 1', advert_name: 'Anuncio 1', platform: 'Meta',
                                  page_name: 'Página 1', social_lead_id: 'social-1', lead_type: 'Facebook Lead Ad',
                                  qualification_channel: 'WhatsApp')
  end

  describe '.copy' do
    it 'copies every blank attribution attribute from the lead onto the deal' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1')

      described_class.copy(deal: deal, lead: lead)

      expect(deal.reload).to have_attributes(campaign_id: 'camp-1', campaign_name: 'Campaña Q1', adset_name: 'Adset 1',
                                             advert_name: 'Anuncio 1', platform: 'Meta', page_name: 'Página 1',
                                             social_lead_id: 'social-1', lead_type: 'Facebook Lead Ad',
                                             qualification_channel: 'WhatsApp')
    end

    it 'never overwrites an attribute the deal already has, even if the lead has a different value' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', campaign_name: 'Campaña ya asignada al deal')

      described_class.copy(deal: deal, lead: lead)

      expect(deal.reload.campaign_name).to eq('Campaña ya asignada al deal')
    end

    it 'is idempotent — calling it twice does not raise or change anything on the second call' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1')

      described_class.copy(deal: deal, lead: lead)
      expect { described_class.copy(deal: deal, lead: lead) }.not_to(change { deal.reload.updated_at })
    end
  end
end
