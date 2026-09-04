require 'rails_helper'

describe RevenueStageEvent do
  let(:account) { create(:account) }

  it 'is valid with account, zoho_deal_id, stage and entered_at' do
    event = described_class.new(account: account, zoho_deal_id: 'deal-1', stage: 'Apartado', entered_at: Time.current)

    expect(event).to be_valid
  end

  it 'requires zoho_deal_id, stage and entered_at' do
    event = described_class.new(account: account)

    expect(event).not_to be_valid
    expect(event.errors[:zoho_deal_id]).to be_present
    expect(event.errors[:stage]).to be_present
    expect(event.errors[:entered_at]).to be_present
  end

  it 'defaults source_system to zoho_stage_history' do
    event = described_class.create!(account: account, zoho_deal_id: 'deal-1', stage: 'Apartado', entered_at: Time.current)

    expect(event.source_system).to eq('zoho_stage_history')
  end

  it 'enforces uniqueness on (account, zoho_deal_id, zoho_history_id) when zoho_history_id is present' do
    described_class.create!(account: account, zoho_deal_id: 'deal-1', stage: 'Apartado', entered_at: Time.current, zoho_history_id: 'hist-1')
    duplicate = described_class.new(account: account, zoho_deal_id: 'deal-1', stage: 'Cerrado ganado', entered_at: Time.current,
                                    zoho_history_id: 'hist-1')

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'enforces uniqueness on (account, zoho_deal_id, stage, entered_at) when zoho_history_id is absent' do
    entered_at = Time.current
    described_class.create!(account: account, zoho_deal_id: 'deal-1', stage: 'Apartado', entered_at: entered_at)
    duplicate = described_class.new(account: account, zoho_deal_id: 'deal-1', stage: 'Apartado', entered_at: entered_at)

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
