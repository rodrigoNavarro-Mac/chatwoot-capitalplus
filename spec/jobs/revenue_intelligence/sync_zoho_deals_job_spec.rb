require 'rails_helper'

describe RevenueIntelligence::SyncZohoDealsJob do
  let(:account) { create(:account) }

  before do
    account.enable_features!('crm_integration')
    allow_any_instance_of(Crm::Zoho::TokenRefreshService).to receive(:token).and_return('fake-token') # rubocop:disable RSpec/AnyInstance
    create(:integrations_hook, :zoho_crm, account: account, status: 'enabled')

    stub_request(:get, %r{zohoapis\.com/crm/v7/Deals/search}).to_return(status: 204, body: '')
  end

  def stub_deals(payloads, more_records: false)
    stub_request(:get, %r{zohoapis\.com/crm/v7/Deals/search})
      .with { |request| CGI.parse(URI(request.uri).query)['criteria'].first.include?('Modified_Time:between:') }
      .to_return(
        status: 200,
        body: { data: payloads, info: { more_records: more_records } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  describe '#perform' do
    it 'creates a revenue_deal for each Zoho Deal returned, mapped via DealMapper' do
      stub_deals([{ 'id' => 'deal-1', 'Stage' => 'Cerrado ganado', 'Desarollo' => 'Fuego' }])

      described_class.new.perform

      deal = account.revenue_deals.find_by(zoho_deal_id: 'deal-1')
      expect(deal).to be_present
      expect(deal.stage).to eq('Cerrado ganado')
      expect(deal.won).to be(true)
      expect(deal.desarrollo).to eq('Fuego')
    end

    it 'is idempotent — running it twice does not duplicate the deal' do
      stub_deals([{ 'id' => 'deal-1' }])

      described_class.new.perform
      described_class.new.perform

      expect(account.revenue_deals.where(zoho_deal_id: 'deal-1').count).to eq(1)
    end

    it 'updates an existing revenue_deal in place when its stage changes in Zoho' do
      stub_deals([{ 'id' => 'deal-1', 'Stage' => 'Qualification' }])
      described_class.new.perform
      stub_deals([{ 'id' => 'deal-1', 'Stage' => 'Cerrado ganado' }])

      described_class.new.perform

      deal = account.revenue_deals.find_by(zoho_deal_id: 'deal-1')
      expect(deal.stage).to eq('Cerrado ganado')
      expect(deal.won).to be(true)
      expect(account.revenue_deals.count).to eq(1)
    end

    it 'advances the sync cursor to "ok" after a successful run' do
      stub_deals([{ 'id' => 'deal-1' }])

      described_class.new.perform

      cursor = account.revenue_sync_cursors.find_by(sync_type: 'deals')
      expect(cursor.last_run_status).to eq('ok')
    end

    it 'continues syncing other hooks when one hook raises' do
      other_account = create(:account)
      other_account.enable_features!('crm_integration')
      create(:integrations_hook, :zoho_crm, account: other_account, status: 'enabled')

      stub_request(:get, %r{zohoapis\.com/crm/v7/Deals/search})
        .with { |request| CGI.parse(URI(request.uri).query)['criteria'].first.include?('Modified_Time:between:') }
        .to_return(
          { status: 500, body: 'boom' },
          { status: 200, body: { data: [{ 'id' => 'deal-ok' }], info: { more_records: false } }.to_json,
            headers: { 'Content-Type' => 'application/json' } }
        )

      expect { described_class.new.perform }.not_to raise_error
      expect(RevenueDeal.where(zoho_deal_id: 'deal-ok')).to exist
    end

    it 'only syncs the given account when an account_id is passed' do
      other_account = create(:account)
      other_account.enable_features!('crm_integration')
      create(:integrations_hook, :zoho_crm, account: other_account, status: 'enabled')
      stub_deals([{ 'id' => 'deal-only-this-account' }])

      described_class.new.perform(account.id)

      expect(account.revenue_deals.where(zoho_deal_id: 'deal-only-this-account')).to exist
      expect(other_account.revenue_deals.count).to eq(0)
    end
  end
end
