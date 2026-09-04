require 'rails_helper'

describe RevenueAppointment do
  let(:account) { create(:account) }

  it 'is valid with an account and zoho_event_id' do
    appointment = described_class.new(account: account, zoho_event_id: 'event-1')

    expect(appointment).to be_valid
  end

  it 'requires zoho_event_id' do
    appointment = described_class.new(account: account)

    expect(appointment).not_to be_valid
    expect(appointment.errors[:zoho_event_id]).to be_present
  end

  it 'does not allow two appointments with the same zoho_event_id in the same account' do
    described_class.create!(account: account, zoho_event_id: 'event-1')
    duplicate = described_class.new(account: account, zoho_event_id: 'event-1')

    expect(duplicate).not_to be_valid
  end

  it 'defaults verified to true — every row in Phase 1 comes from a real Zoho Event' do
    appointment = described_class.create!(account: account, zoho_event_id: 'event-1')

    expect(appointment.verified).to be(true)
  end
end
