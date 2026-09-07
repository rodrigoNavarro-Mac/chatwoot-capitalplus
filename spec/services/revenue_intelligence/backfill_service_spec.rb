require 'rails_helper'

describe RevenueIntelligence::BackfillService do
  let(:account) { create(:account) }
  # Chico a propósito: los tests de #perform! bajo chunking real ahora simulan cada tramo con una
  # escritura real a la BD (~1 iteración por DEFAULT_CHUNK de 1 día) — un rango de meses sería
  # correcto pero innecesariamente lento sin agregar cobertura real.
  let(:from) { 3.days.ago }

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

  describe '#seed_cursors! (vía send, comportamiento aislado de la orquestación de #perform!)' do
    it 'sets last_synced_at to `from` for all 4 sync types when they do not exist yet' do
      described_class.new(account: account, from: from).send(:seed_cursors!)

      cursors = account.revenue_sync_cursors.pluck(:sync_type, :last_synced_at).to_h
      expect(cursors.keys).to contain_exactly('leads', 'deals', 'stage_history', 'meetings')
      cursors.each_value { |time| expect(time).to be_within(1.second).of(from) }
    end

    it 'rewinds a cursor that is already more recent than `from`, to force re-covering that range' do
      recent = 1.day.ago
      account.revenue_sync_cursors.create!(sync_type: 'leads', last_synced_at: recent)

      described_class.new(account: account, from: from).send(:seed_cursors!)

      cursor = RevenueSyncCursor.find_by(account_id: account.id, sync_type: 'leads')
      expect(cursor.last_synced_at).to be_within(1.second).of(from)
    end

    it 'does not rewind a cursor that is already older than `from`' do
      older = 3.months.ago
      account.revenue_sync_cursors.create!(sync_type: 'leads', last_synced_at: older)

      described_class.new(account: account, from: from).send(:seed_cursors!)

      cursor = RevenueSyncCursor.find_by(account_id: account.id, sync_type: 'leads')
      expect(cursor.last_synced_at).to be_within(1.second).of(older)
    end
  end

  describe '#perform!' do
    # Simula lo que el job real haría con un tramo exitoso: avanza el cursor hasta `until_at`. Sin
    # esto, chunked_sync jamás vería el cursor moverse y el loop `until cursor_since >= Time.current`
    # no terminaría nunca.
    def stub_successful_sync(job_class, sync_type)
      allow(job_class).to receive(:perform_now) do |_account_id, until_at: nil|
        # RevenueSyncCursor.find_by directo, NO account.revenue_sync_cursors.find_by — la
        # asociación puede quedar cacheada ("loaded") de una llamada anterior en el mismo test
        # (ej. seed_cursors!) y entonces #find_by filtra ese array ya cargado en vez de ir a la
        # base de datos, devolviendo nil si esa fila no estaba en el array al momento de cargarse
        # — el update! nunca se ejecuta y el cursor queda congelado para siempre (bug real
        # encontrado mientras se escribía este mismo test).
        RevenueSyncCursor.find_by(account_id: account.id, sync_type: sync_type)
                         &.update!(last_synced_at: until_at, last_run_status: 'ok', last_error: nil)
      end
    end

    before do
      stub_successful_sync(RevenueIntelligence::SyncZohoLeadsJob, 'leads')
      stub_successful_sync(RevenueIntelligence::SyncZohoDealsJob, 'deals')
      allow(RevenueIntelligence::SyncZohoStageHistoryJob).to receive(:perform_now)
      allow(RevenueIntelligence::SyncZohoMeetingsJob).to receive(:perform_now)
      allow(RevenueIntelligence::ResolveIdentityJob).to receive(:perform_now)
    end

    it 'seeds stage_history/meetings to `from` (no son chunkeables, un solo perform_now sin until_at)' do
      described_class.new(account: account, from: from).perform!

      cursors = account.revenue_sync_cursors.pluck(:sync_type, :last_synced_at).to_h
      expect(cursors['stage_history']).to be_within(1.second).of(from)
      expect(cursors['meetings']).to be_within(1.second).of(from)
    end

    it 'drives the leads/deals cursors all the way to the present via chunked calls' do
      described_class.new(account: account, from: from).perform!

      cursors = account.revenue_sync_cursors.pluck(:sync_type, :last_synced_at).to_h
      expect(cursors['leads']).to be_within(2.seconds).of(Time.current)
      expect(cursors['deals']).to be_within(2.seconds).of(Time.current)
    end

    it 'calls each sync job and the identity resolver with the account id' do
      described_class.new(account: account, from: from).perform!

      expect(RevenueIntelligence::SyncZohoLeadsJob).to have_received(:perform_now).with(account.id, until_at: kind_of(Time)).at_least(:once)
      expect(RevenueIntelligence::SyncZohoDealsJob).to have_received(:perform_now).with(account.id, until_at: kind_of(Time)).at_least(:once)
      expect(RevenueIntelligence::SyncZohoStageHistoryJob).to have_received(:perform_now).with(account.id)
      expect(RevenueIntelligence::SyncZohoMeetingsJob).to have_received(:perform_now).with(account.id)
      expect(RevenueIntelligence::ResolveIdentityJob).to have_received(:perform_now).with(account.id)
    end

    describe 'chunking adaptativo cuando un tramo pega contra el límite de 2000 de Zoho' do
      let(:from) { 3.days.ago }

      it 'halves the chunk and retries from the same point when a chunk hits LIMIT_REACHED, then succeeds' do
        attempt = 0
        allow(RevenueIntelligence::SyncZohoLeadsJob).to receive(:perform_now) do |_account_id, until_at: nil|
          attempt += 1
          cursor = RevenueSyncCursor.find_by(account_id: account.id, sync_type: 'leads')
          if attempt == 1
            cursor.update!(last_run_status: 'failed', last_error: 'Zoho CRM API error: 400 - {"code":"LIMIT_REACHED"}')
          else
            cursor.update!(last_synced_at: until_at, last_run_status: 'ok', last_error: nil)
          end
        end

        expect { described_class.new(account: account, from: from).perform! }.not_to raise_error
        expect(RevenueIntelligence::SyncZohoLeadsJob).to have_received(:perform_now).at_least(2).times
        expect(RevenueSyncCursor.find_by(account_id: account.id, sync_type: 'leads').last_synced_at).to be_within(2.seconds).of(Time.current)
      end

      it 'raises a clear error when even the minimum chunk still hits LIMIT_REACHED' do
        allow(RevenueIntelligence::SyncZohoLeadsJob).to receive(:perform_now) do |_account_id, **_kwargs|
          RevenueSyncCursor.find_by(account_id: account.id, sync_type: 'leads')
                           .update!(last_run_status: 'failed', last_error: 'Zoho CRM API error: 400 - {"code":"LIMIT_REACHED"}')
        end

        expect { described_class.new(account: account, from: from).perform! }.to raise_error(/tramo mínimo/)
      end

      it 'raises immediately, without halving, on a failure unrelated to LIMIT_REACHED' do
        allow(RevenueIntelligence::SyncZohoLeadsJob).to receive(:perform_now) do |_account_id, **_kwargs|
          RevenueSyncCursor.find_by(account_id: account.id, sync_type: 'leads').update!(last_run_status: 'failed', last_error: 'boom')
        end

        expect { described_class.new(account: account, from: from).perform! }.to raise_error(/boom/)
        expect(RevenueIntelligence::SyncZohoLeadsJob).to have_received(:perform_now).once
      end
    end
  end
end
