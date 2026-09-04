require 'rails_helper'

describe RevenueLeadJourney do
  let(:account) { create(:account) }
  let(:revenue_lead) { account.revenue_leads.create!(zoho_lead_id: 'lead-1') }

  it 'is valid with an account and a revenue_lead' do
    journey = described_class.new(account: account, revenue_lead: revenue_lead)

    expect(journey).to be_valid
  end

  it 'does not allow two journeys for the same revenue_lead in the same account' do
    described_class.create!(account: account, revenue_lead: revenue_lead)
    duplicate = described_class.new(account: account, revenue_lead: revenue_lead)

    expect(duplicate).not_to be_valid
  end

  it 'defaults activity counters and won/lost to zero/false' do
    journey = described_class.create!(account: account, revenue_lead: revenue_lead)

    expect(journey.incoming_messages).to eq(0)
    expect(journey.calls_attempted).to eq(0)
    expect(journey.won).to be(false)
    expect(journey.lost).to be(false)
  end

  describe 'scopes' do
    let!(:won_journey) do
      described_class.create!(account: account, revenue_lead: account.revenue_leads.create!(zoho_lead_id: 'lead-won'), won: true)
    end
    let!(:lost_journey) do
      described_class.create!(account: account, revenue_lead: account.revenue_leads.create!(zoho_lead_id: 'lead-lost'), lost: true)
    end

    it '.won returns only won journeys' do
      expect(account.revenue_lead_journeys.won).to contain_exactly(won_journey)
    end

    it '.lost returns only lost journeys' do
      expect(account.revenue_lead_journeys.lost).to contain_exactly(lost_journey)
    end
  end
end
