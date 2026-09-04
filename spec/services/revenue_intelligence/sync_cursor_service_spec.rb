require 'rails_helper'

describe RevenueIntelligence::SyncCursorService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account, 'leads') }

  describe '#since' do
    it 'returns nil when no cursor exists yet' do
      expect(service.since).to be_nil
    end

    it 'returns the last_synced_at of an existing cursor' do
      time = 1.hour.ago
      account.revenue_sync_cursors.create!(sync_type: 'leads', last_synced_at: time)

      expect(service.since).to be_within(1.second).of(time)
    end
  end

  describe '#advance!' do
    it 'creates the cursor if it does not exist yet and marks it ok' do
      time = Time.current

      service.advance!(time)

      cursor = account.revenue_sync_cursors.find_by(sync_type: 'leads')
      expect(cursor.last_synced_at).to be_within(1.second).of(time)
      expect(cursor.last_run_status).to eq('ok')
    end

    it 'clears a previously recorded error' do
      service.record_error!('boom')

      service.advance!(Time.current)

      expect(account.revenue_sync_cursors.find_by(sync_type: 'leads').last_error).to be_nil
    end

    it 'does not create duplicate cursors for the same account and sync_type across calls' do
      described_class.new(account, 'leads').advance!(Time.current)
      described_class.new(account, 'leads').advance!(Time.current)

      expect(account.revenue_sync_cursors.where(sync_type: 'leads').count).to eq(1)
    end
  end

  describe '#record_error!' do
    it 'stores the error message and marks the cursor as failed' do
      service.record_error!('boom')

      cursor = account.revenue_sync_cursors.find_by(sync_type: 'leads')
      expect(cursor.last_run_status).to eq('failed')
      expect(cursor.last_error).to eq('boom')
    end
  end

  it 'keeps separate cursors per sync_type for the same account' do
    described_class.new(account, 'leads').advance!(Time.current)
    described_class.new(account, 'deals').advance!(Time.current)

    expect(account.revenue_sync_cursors.pluck(:sync_type)).to contain_exactly('leads', 'deals')
  end
end
