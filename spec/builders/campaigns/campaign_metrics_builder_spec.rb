require 'rails_helper'

describe Campaigns::CampaignMetricsBuilder do
  let(:account) { create(:account) }
  let(:campaign) do
    create(:campaign, account: account, template_params: { 'name' => 'promo_a' },
                      template_variant_b: { 'template_params' => { 'name' => 'promo_b' }, 'message' => 'Hola B' })
  end

  def delivery(variant, index, **attrs)
    campaign.campaign_message_deliveries.create!(
      account_id: account.id, audience_type: 'csv', phone_number: "+52155#{variant == 'A' ? 1 : 2}000000#{index}",
      template_variant: variant, source_id: "wamid.#{variant}#{index}", status: 'sent', sent_at: 1.day.ago, **attrs
    )
  end

  it 'breaks the funnel down per template in an A/B test' do
    delivery('A', 1, delivered_at: 1.day.ago, responded_at: 1.hour.ago)
    delivery('A', 2, delivered_at: 1.day.ago)
    delivery('B', 1, delivered_at: 1.day.ago, read_at: 1.day.ago)
    campaign.campaign_message_deliveries.create!(account_id: account.id, audience_type: 'csv', phone_number: '+5215530000001',
                                                 template_variant: 'B', status: 'failed', failed_at: 1.day.ago)

    variants = described_class.new(campaign).build[:variants]

    expect(variants['A']).to include(template_name: 'promo_a', attempted: 2, sent: 2, delivered: 2, responded: 1, response_rate: 50.0)
    expect(variants['B']).to include(template_name: 'promo_b', attempted: 2, sent: 1, read: 1, failed: 1, responded: 0, response_rate: 0.0)
  end

  it 'keeps the overall totals across both templates' do
    delivery('A', 1)
    delivery('B', 1, responded_at: 1.hour.ago)

    expect(described_class.new(campaign).build).to include(attempted: 2, sent: 2, responded: 1, response_rate: 50.0)
  end

  it 'has no variant breakdown for a single-template campaign' do
    campaign.update!(template_variant_b: nil)

    expect(described_class.new(campaign).build[:variants]).to be_nil
  end
end
