require 'rails_helper'

describe RevenueContact do
  let(:account) { create(:account) }

  it 'is valid with an account and lifecycle timestamps' do
    contact = described_class.new(account: account, first_seen_at: Time.current, last_seen_at: Time.current)

    expect(contact).to be_valid
  end

  it 'requires first_seen_at and last_seen_at' do
    contact = described_class.new(account: account)

    expect(contact).not_to be_valid
    expect(contact.errors[:first_seen_at]).to be_present
    expect(contact.errors[:last_seen_at]).to be_present
  end

  it 'does not allow two contacts with the same normalized_phone in the same account' do
    described_class.create!(account: account, normalized_phone: '+529981234567', first_seen_at: Time.current, last_seen_at: Time.current)
    duplicate = described_class.new(account: account, normalized_phone: '+529981234567', first_seen_at: Time.current, last_seen_at: Time.current)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:normalized_phone]).to be_present
  end

  it 'allows multiple contacts with a nil normalized_phone in the same account' do
    described_class.create!(account: account, first_seen_at: Time.current, last_seen_at: Time.current)
    second = described_class.new(account: account, first_seen_at: Time.current, last_seen_at: Time.current)

    expect(second).to be_valid
  end

  it 'allows the same normalized_phone across different accounts' do
    other_account = create(:account)
    described_class.create!(account: account, normalized_phone: '+529981234567', first_seen_at: Time.current, last_seen_at: Time.current)
    other = described_class.new(account: other_account, normalized_phone: '+529981234567', first_seen_at: Time.current, last_seen_at: Time.current)

    expect(other).to be_valid
  end

  it 'does not allow two contacts with the same zoho_lead_id in the same account' do
    described_class.create!(account: account, zoho_lead_id: 'lead-1', first_seen_at: Time.current, last_seen_at: Time.current)
    duplicate = described_class.new(account: account, zoho_lead_id: 'lead-1', first_seen_at: Time.current, last_seen_at: Time.current)

    expect(duplicate).not_to be_valid
  end
end
