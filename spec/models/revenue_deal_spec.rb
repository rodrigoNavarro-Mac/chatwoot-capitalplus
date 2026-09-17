require 'rails_helper'

describe RevenueDeal do
  let(:account) { create(:account) }

  it 'is valid with an account and zoho_deal_id' do
    deal = described_class.new(account: account, zoho_deal_id: 'deal-1')

    expect(deal).to be_valid
  end

  it 'requires zoho_deal_id' do
    deal = described_class.new(account: account)

    expect(deal).not_to be_valid
    expect(deal.errors[:zoho_deal_id]).to be_present
  end

  it 'does not allow two deals with the same zoho_deal_id in the same account' do
    described_class.create!(account: account, zoho_deal_id: 'deal-1')
    duplicate = described_class.new(account: account, zoho_deal_id: 'deal-1')

    expect(duplicate).not_to be_valid
  end

  it 'defaults won and lost to false' do
    deal = described_class.create!(account: account, zoho_deal_id: 'deal-1')

    expect(deal.won).to be(false)
    expect(deal.lost).to be(false)
  end

  describe 'VISIT_STAGES' do
    it 'includes the real reference_value for "Cotizado con visita" ("Cotizado"), not its English actual_value' do
      expect(described_class::VISIT_STAGES).to include('Cotizado')
      expect(described_class::VISIT_STAGES).not_to include('Needs Analysis')
    end

    it 'does not include a "sin cita" quote stage, since that does not imply a visit happened' do
      expect(described_class::VISIT_STAGES).not_to include('Cotizado sin cita.')
      expect(described_class::VISIT_STAGES).not_to include('Cotizado sin cita')
    end

    it 'includes RESERVED_STAGE and WON_STAGE, since reaching either implies the visit already happened' do
      expect(described_class::VISIT_STAGES).to include(described_class::RESERVED_STAGE, described_class::WON_STAGE)
    end
  end

  describe 'scopes' do
    let!(:won_deal) { described_class.create!(account: account, zoho_deal_id: 'deal-won', won: true) }
    let!(:lost_deal) { described_class.create!(account: account, zoho_deal_id: 'deal-lost', lost: true) }
    let!(:open_deal) { described_class.create!(account: account, zoho_deal_id: 'deal-open') }

    it '.won returns only won deals' do
      expect(account.revenue_deals.won).to contain_exactly(won_deal)
    end

    it '.lost returns only lost deals' do
      expect(account.revenue_deals.lost).to contain_exactly(lost_deal)
    end

    it '.open returns only deals that are neither won nor lost' do
      expect(account.revenue_deals.open).to contain_exactly(open_deal)
    end
  end
end
