require 'rails_helper'

describe RevenueRollup do
  let(:account) { create(:account) }

  it 'is valid with account, a known dimension_type, dimension_id, metric and date' do
    rollup = described_class.new(account: account, date: Date.current, dimension_type: 'funnel', dimension_id: 'Fuego',
                                 metric: 'leads_created')

    expect(rollup).to be_valid
  end

  it 'rejects an unknown dimension_type' do
    rollup = described_class.new(account: account, date: Date.current, dimension_type: 'unknown', dimension_id: 'x', metric: 'y')

    expect(rollup).not_to be_valid
    expect(rollup.errors[:dimension_type]).to be_present
  end

  it 'does not allow two rows with the same (date, dimension_type, dimension_id, metric) in the same account' do
    described_class.create!(account: account, date: Date.current, dimension_type: 'funnel', dimension_id: 'Fuego', metric: 'leads_created')
    duplicate = described_class.new(account: account, date: Date.current, dimension_type: 'funnel', dimension_id: 'Fuego',
                                    metric: 'leads_created')

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'defaults count to 0 and sum_value to 0.0' do
    rollup = described_class.create!(account: account, date: Date.current, dimension_type: 'funnel', dimension_id: 'Fuego',
                                     metric: 'leads_created')

    expect(rollup.count).to eq(0)
    expect(rollup.sum_value.to_f).to eq(0.0)
  end
end
