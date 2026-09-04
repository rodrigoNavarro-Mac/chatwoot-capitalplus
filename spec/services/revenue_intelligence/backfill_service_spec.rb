require 'rails_helper'

describe RevenueIntelligence::BackfillService do
  let(:account) { create(:account) }
  let(:from) { 2.months.ago }

  before do
    account.enable_features!('crm_integration')
    allow_any_instance_of(Crm::Zoho::TokenRefreshService).to receive(:token).and_return('fake-token') # rubocop:disable RSpec/AnyInstance
    create(:integrations_hook, :zoho_crm, account: account, status: 'enabled')
  end

  describe '#preview_counts' do
    it 'reports the first-page count for leads and deals modified since `from`' do
      stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/search})
        .to_return(status: 200, body: { data: [{ 'id' => 'lead-1' }], info: { more_records: false } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{zohoapis\.com/crm/v7/Deals/search})
        .to_return(status: 200, body: { data: [{ 'id' => 'deal-1' }, { 'id' => 'deal-2' }], info: { more_records: true } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      counts = described_class.new(account: account, from: from).preview_counts

      expect(counts[:leads]).to eq('1')
      expect(counts[:deals]).to eq('2+ (hay más páginas)')
    end
  end

  describe '#perform!' do
    before do
      allow(RevenueIntelligence::SyncZohoLeadsJob).to receive(:perform_now)
      allow(RevenueIntelligence::SyncZohoDealsJob).to receive(:perform_now)
      allow(RevenueIntelligence::SyncZohoStageHistoryJob).to receive(:perform_now)
      allow(RevenueIntelligence::SyncZohoMeetingsJob).to receive(:perform_now)
      allow(RevenueIntelligence::ResolveIdentityJob).to receive(:perform_now)
    end

    it 'seeds all 4 sync cursors to `from` when they do not exist yet' do
      described_class.new(account: account, from: from).perform!

      cursors = account.revenue_sync_cursors.pluck(:sync_type, :last_synced_at).to_h
      expect(cursors.keys).to contain_exactly('leads', 'deals', 'stage_history', 'meetings')
      cursors.each_value { |time| expect(time).to be_within(1.second).of(from) }
    end

    it 'calls each sync job and the identity resolver with the account id' do
      expect(RevenueIntelligence::SyncZohoLeadsJob).to receive(:perform_now).with(account.id)
      expect(RevenueIntelligence::SyncZohoDealsJob).to receive(:perform_now).with(account.id)
      expect(RevenueIntelligence::SyncZohoStageHistoryJob).to receive(:perform_now).with(account.id)
      expect(RevenueIntelligence::SyncZohoMeetingsJob).to receive(:perform_now).with(account.id)
      expect(RevenueIntelligence::ResolveIdentityJob).to receive(:perform_now).with(account.id)

      described_class.new(account: account, from: from).perform!
    end

    it 'rewinds a cursor that is already more recent than `from`, to force re-covering that range' do
      recent = 1.day.ago
      account.revenue_sync_cursors.create!(sync_type: 'leads', last_synced_at: recent)

      described_class.new(account: account, from: from).perform!

      cursor = account.revenue_sync_cursors.find_by(sync_type: 'leads')
      expect(cursor.last_synced_at).to be_within(1.second).of(from)
    end

    it 'does not advance a cursor that is already older than `from`' do
      older = 3.months.ago
      account.revenue_sync_cursors.create!(sync_type: 'leads', last_synced_at: older)

      described_class.new(account: account, from: from).perform!

      cursor = account.revenue_sync_cursors.find_by(sync_type: 'leads')
      expect(cursor.last_synced_at).to be_within(1.second).of(older)
    end
  end
end
