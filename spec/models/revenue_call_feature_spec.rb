require 'rails_helper'

describe RevenueCallFeature do
  let(:account) { create(:account) }

  it 'is valid with an account, call_id and call_analysis_id' do
    feature = described_class.new(account: account, call_id: 1, call_analysis_id: 1)

    expect(feature).to be_valid
  end

  it 'requires call_id and call_analysis_id' do
    feature = described_class.new(account: account)

    expect(feature).not_to be_valid
    expect(feature.errors[:call_id]).to be_present
    expect(feature.errors[:call_analysis_id]).to be_present
  end

  it 'does not allow two features for the same call_id in the same account' do
    described_class.create!(account: account, call_id: 1, call_analysis_id: 1)
    duplicate = described_class.new(account: account, call_id: 1, call_analysis_id: 2)

    expect(duplicate).not_to be_valid
  end

  it 'defaults boolean qualification columns and counters to false/zero' do
    feature = described_class.create!(account: account, call_id: 1, call_analysis_id: 1)

    expect(feature.qual_presupuesto).to be(false)
    expect(feature.cta_used).to be(false)
    expect(feature.qualification_count).to eq(0)
  end
end
