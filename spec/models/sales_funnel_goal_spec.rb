require 'rails_helper'

describe SalesFunnelGoal do
  let(:account) { create(:account) }

  it 'is valid with a stage from STAGES, a target_percent between 0 and 100, and a period_month' do
    goal = described_class.new(account: account, development_key: 'torre-1', stage: 'leads',
                                period_month: Date.new(2026, 7, 15), target_percent: 30)

    expect(goal).to be_valid
  end

  it 'rejects a stage outside STAGES' do
    goal = described_class.new(account: account, development_key: 'torre-1', stage: 'not_a_stage',
                                period_month: Date.current, target_percent: 30)

    expect(goal).not_to be_valid
  end

  it 'rejects a target_percent outside 0..100' do
    goal = described_class.new(account: account, development_key: 'torre-1', stage: 'leads',
                                period_month: Date.current, target_percent: 101)

    expect(goal).not_to be_valid
  end

  it 'normalizes period_month to the beginning of the month' do
    goal = described_class.create!(account: account, development_key: 'torre-1', stage: 'leads',
                                    period_month: Date.new(2026, 7, 15), target_percent: 30)

    expect(goal.period_month).to eq(Date.new(2026, 7, 1))
  end

  it 'enforces one goal per account/development_key/stage/period_month' do
    described_class.create!(account: account, development_key: 'torre-1', stage: 'leads',
                             period_month: Date.new(2026, 7, 1), target_percent: 30)
    duplicate = described_class.new(account: account, development_key: 'torre-1', stage: 'leads',
                                     period_month: Date.new(2026, 7, 15), target_percent: 50)

    expect(duplicate).not_to be_valid
  end

  it 'allows the same stage for a different development_key in the same month' do
    described_class.create!(account: account, development_key: 'torre-1', stage: 'leads',
                             period_month: Date.new(2026, 7, 1), target_percent: 30)
    other = described_class.new(account: account, development_key: 'torre-2', stage: 'leads',
                                 period_month: Date.new(2026, 7, 1), target_percent: 50)

    expect(other).to be_valid
  end
end
