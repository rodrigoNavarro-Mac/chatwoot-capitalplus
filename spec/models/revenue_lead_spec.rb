require 'rails_helper'

describe RevenueLead do
  let(:account) { create(:account) }

  it 'is valid with an account and zoho_lead_id' do
    lead = described_class.new(account: account, zoho_lead_id: 'lead-1')

    expect(lead).to be_valid
  end

  it 'requires zoho_lead_id' do
    lead = described_class.new(account: account)

    expect(lead).not_to be_valid
    expect(lead.errors[:zoho_lead_id]).to be_present
  end

  it 'does not allow two leads with the same zoho_lead_id in the same account' do
    described_class.create!(account: account, zoho_lead_id: 'lead-1')
    duplicate = described_class.new(account: account, zoho_lead_id: 'lead-1')

    expect(duplicate).not_to be_valid
  end

  it 'allows the same zoho_lead_id across different accounts' do
    other_account = create(:account)
    described_class.create!(account: account, zoho_lead_id: 'lead-1')
    other = described_class.new(account: other_account, zoho_lead_id: 'lead-1')

    expect(other).to be_valid
  end

  it 'defaults attempt_count and reassignment_count to zero' do
    lead = described_class.create!(account: account, zoho_lead_id: 'lead-1')

    expect(lead.attempt_count).to eq(0)
    expect(lead.reassignment_count).to eq(0)
  end

  it 'is created without a resolved identity by default' do
    lead = described_class.create!(account: account, zoho_lead_id: 'lead-1')

    expect(lead.revenue_contact_id).to be_nil
  end
end
