require 'rails_helper'

describe RevenueIntelligence::SyncZohoLeadsJob do
  let(:account) { create(:account) }

  before do
    account.enable_features!('crm_integration')
    allow_any_instance_of(Crm::Zoho::TokenRefreshService).to receive(:token).and_return('fake-token') # rubocop:disable RSpec/AnyInstance
    create(:integrations_hook, :zoho_crm, account: account, status: 'enabled')

    # Catch-all: evita depender del orden exacto de hooks/cuentas preexistentes en el entorno de
    # test — los stubs específicos de cada test, registrados después, tienen prioridad.
    stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/search}).to_return(status: 204, body: '')
  end

  def stub_leads(payloads, more_records: false)
    stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/search})
      .with { |request| CGI.parse(URI(request.uri).query)['criteria'].first.include?('Modified_Time:between:') }
      .to_return(
        status: 200,
        body: { data: payloads, info: { more_records: more_records } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  describe '#perform' do
    it 'creates a revenue_lead for each Zoho Lead returned, mapped via LeadMapper' do
      stub_leads([{ 'id' => 'lead-1', 'Lead_Status' => 'Contactado', 'Desarrollo' => 'Fuego' }])

      described_class.new.perform

      lead = account.revenue_leads.find_by(zoho_lead_id: 'lead-1')
      expect(lead).to be_present
      expect(lead.lead_status).to eq('Contactado')
      expect(lead.desarrollo).to eq('Fuego')
      expect(lead.synced_at).to be_present
    end

    it 'is idempotent — running it twice does not duplicate the lead' do
      stub_leads([{ 'id' => 'lead-1' }])

      described_class.new.perform
      described_class.new.perform

      expect(account.revenue_leads.where(zoho_lead_id: 'lead-1').count).to eq(1)
    end

    it 'advances the sync cursor to "ok" after a successful run' do
      stub_leads([{ 'id' => 'lead-1' }])

      described_class.new.perform

      cursor = account.revenue_sync_cursors.find_by(sync_type: 'leads')
      expect(cursor.last_run_status).to eq('ok')
      expect(cursor.last_synced_at).to be_present
    end

    it 'continues syncing other hooks when one hook raises' do
      other_account = create(:account)
      other_account.enable_features!('crm_integration')
      create(:integrations_hook, :zoho_crm, account: other_account, status: 'enabled')

      stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/search})
        .with { |request| CGI.parse(URI(request.uri).query)['criteria'].first.include?('Modified_Time:between:') }
        .to_return(
          { status: 500, body: 'boom' },
          { status: 200, body: { data: [{ 'id' => 'lead-ok' }], info: { more_records: false } }.to_json,
            headers: { 'Content-Type' => 'application/json' } }
        )

      expect { described_class.new.perform }.not_to raise_error
      expect(RevenueLead.where(zoho_lead_id: 'lead-ok')).to exist
    end

    it 'only syncs the given account when an account_id is passed' do
      other_account = create(:account)
      other_account.enable_features!('crm_integration')
      create(:integrations_hook, :zoho_crm, account: other_account, status: 'enabled')
      stub_leads([{ 'id' => 'lead-only-this-account' }])

      described_class.new.perform(account.id)

      expect(account.revenue_leads.where(zoho_lead_id: 'lead-only-this-account')).to exist
      expect(other_account.revenue_leads.count).to eq(0)
    end

    it 'follows pagination until more_records is false' do
      stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/search})
        .with { |request| CGI.parse(URI(request.uri).query)['page'].first == '1' }
        .to_return(status: 200, body: { data: [{ 'id' => 'lead-page-1' }], info: { more_records: true } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/search})
        .with { |request| CGI.parse(URI(request.uri).query)['page'].first == '2' }
        .to_return(status: 200, body: { data: [{ 'id' => 'lead-page-2' }], info: { more_records: false } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      described_class.new.perform

      expect(account.revenue_leads.pluck(:zoho_lead_id)).to contain_exactly('lead-page-1', 'lead-page-2')
    end
  end
end
