require 'rails_helper'

describe Campaigns::TemplateVariantPicker do
  let(:account) { create(:account) }
  let(:template_a) { { 'name' => 'promo_a', 'language' => 'es_MX', 'processed_params' => {} } }
  let(:template_b) { { 'name' => 'promo_b', 'language' => 'es_MX', 'processed_params' => {} } }
  let(:campaign) do
    create(:campaign, account: account, message: 'Hola A', template_params: template_a,
                      template_variant_b: { 'template_params' => template_b, 'message' => 'Hola B' })
  end
  let(:phones) { (1..1000).map { |i| format('+52155%08d', i) } }

  it 'uses the single campaign template when there is no variant B' do
    single = create(:campaign, account: account, message: 'Hola', template_params: template_a)
    variant = described_class.new(campaign: single).for_phone('+5215511112222')

    expect(variant.key).to be_nil
    expect(variant.template_params).to eq(template_a)
    expect(variant.message).to eq('Hola')
  end

  it 'gives each variant its own template and message' do
    variants = phones.map { |phone| described_class.new(campaign: campaign).for_phone(phone) }.uniq(&:key)

    expect(variants.to_h { |v| [v.key, [v.template_params['name'], v.message]] })
      .to eq('A' => ['promo_a', 'Hola A'], 'B' => ['promo_b', 'Hola B'])
  end

  it 'always assigns a phone to the same variant, whatever the 52/521 prefix' do
    picker = described_class.new(campaign: campaign)
    keys = ['+5215511112222', '+525511112222', '5511112222'].map { |phone| picker.for_phone(phone).key }

    expect(keys.uniq.size).to eq(1)
    expect(described_class.new(campaign: campaign.reload).for_phone('+525511112222').key).to eq(keys.first)
  end

  it 'splits the audience according to ab_split' do
    campaign.update!(ab_split: 70)
    share_a = phones.count { |phone| described_class.new(campaign: campaign).for_phone(phone).key == 'A' } / phones.size.to_f

    expect(share_a).to be_within(0.05).of(0.7)
  end

  it 'treats a variant B without a template as no A/B test' do
    campaign.update!(template_variant_b: { 'template_params' => {}, 'message' => 'Hola B' })

    expect(described_class.ab_test?(campaign)).to be false
    expect(described_class.new(campaign: campaign).for_phone('+5215511112222').key).to be_nil
  end
end
