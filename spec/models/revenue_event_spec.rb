require 'rails_helper'

describe RevenueEvent do
  let(:account) { create(:account) }

  it 'is valid with account, a known event_type, event_at, source_system and source_id' do
    event = described_class.new(account: account, event_type: 'lead_created', event_at: Time.current,
                                source_system: 'revenue_lead', source_id: '1')

    expect(event).to be_valid
  end

  it 'rejects an unknown event_type' do
    event = described_class.new(account: account, event_type: 'quote_created', event_at: Time.current,
                                source_system: 'revenue_deal', source_id: '1')

    expect(event).not_to be_valid
    expect(event.errors[:event_type]).to be_present
  end

  it 'requires event_at, source_system and source_id' do
    event = described_class.new(account: account, event_type: 'lead_created')

    expect(event).not_to be_valid
    expect(event.errors[:event_at]).to be_present
    expect(event.errors[:source_system]).to be_present
    expect(event.errors[:source_id]).to be_present
  end

  it 'does not allow two events with the same (source_system, event_type, source_id) in the same account' do
    described_class.create!(account: account, event_type: 'lead_created', event_at: Time.current,
                            source_system: 'revenue_lead', source_id: '1')
    duplicate = described_class.new(account: account, event_type: 'lead_created', event_at: Time.current,
                                    source_system: 'revenue_lead', source_id: '1')

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'allows the same source_id with a different event_type (e.g. stage_changed + closed_won on the same row)' do
    described_class.create!(account: account, event_type: 'stage_changed', event_at: Time.current,
                            source_system: 'revenue_stage_event', source_id: '1')
    other = described_class.new(account: account, event_type: 'closed_won', event_at: Time.current,
                                source_system: 'revenue_stage_event', source_id: '1')

    expect(other).to be_valid
  end
end
