require 'rails_helper'

describe RevenueIntelligence::SyncZohoStageHistoryJob do
  let(:account) { create(:account) }

  before do
    account.enable_features!('crm_integration')
    allow_any_instance_of(Crm::Zoho::TokenRefreshService).to receive(:token).and_return('fake-token') # rubocop:disable RSpec/AnyInstance
    create(:integrations_hook, :zoho_crm, account: account, status: 'enabled')

    stub_request(:get, %r{zohoapis\.com/crm/v7/Deals/[\w-]+/Stage_History}).to_return(status: 204, body: '')
  end

  def stub_stage_history(zoho_deal_id, rows)
    stub_request(:get, %r{zohoapis\.com/crm/v7/Deals/#{zoho_deal_id}/Stage_History})
      .to_return(status: 200, body: { data: rows }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#perform' do
    it 'creates revenue_stage_events for a touched deal, using its Created_Time as the fallback entered_at' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', created_at_source: Time.zone.parse('2025-11-20T00:00:00-06:00'))
      stub_stage_history('deal-1', [
                           { 'id' => 'hist-1', 'Stage' => 'Cotizado con visita', 'Moved_To__s' => 'Apartado',
                             'Stage_Duration_Calendar_Days' => 6, 'Modified_Time' => '2025-12-02T11:52:59-06:00' },
                           { 'id' => 'hist-2', 'Stage' => 'Apartado', 'Moved_To__s' => nil,
                             'Stage_Duration_Calendar_Days' => nil, 'Modified_Time' => '2025-12-08T17:08:39-06:00' }
                         ])

      described_class.new.perform

      events = deal.revenue_stage_events.order(:entered_at)
      expect(events.count).to eq(2)
      expect(events.first.entered_at).to eq(deal.created_at_source)
      expect(events.first.exited_at).to eq(Time.zone.parse('2025-12-02T11:52:59-06:00'))
      expect(events.last.exited_at).to be_nil
      expect(events.last.revenue_contact_id).to eq(deal.revenue_contact_id)
    end

    it 'is idempotent — running it twice does not duplicate stage events' do
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', created_at_source: Time.current)
      stub_stage_history('deal-1', [{ 'id' => 'hist-1', 'Stage' => 'Apartado', 'Moved_To__s' => nil,
                                      'Stage_Duration_Calendar_Days' => nil, 'Modified_Time' => Time.current.iso8601 }])

      described_class.new.perform
      described_class.new.perform

      expect(RevenueStageEvent.where(zoho_history_id: 'hist-1').count).to eq(1)
    end

    it 'skips deals without any stage history rows' do
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', created_at_source: Time.current)

      expect { described_class.new.perform }.not_to change(RevenueStageEvent, :count)
    end

    it 'continues with other deals when one deal raises' do
      account.revenue_deals.create!(zoho_deal_id: 'deal-broken', created_at_source: Time.current)
      account.revenue_deals.create!(zoho_deal_id: 'deal-ok', created_at_source: Time.current)
      stub_request(:get, %r{zohoapis\.com/crm/v7/Deals/deal-broken/Stage_History}).to_return(status: 500, body: 'boom')
      stub_stage_history('deal-ok', [{ 'id' => 'hist-1', 'Stage' => 'Apartado', 'Moved_To__s' => nil,
                                       'Stage_Duration_Calendar_Days' => nil, 'Modified_Time' => Time.current.iso8601 }])

      expect { described_class.new.perform }.not_to raise_error
      expect(RevenueStageEvent.where(zoho_history_id: 'hist-1')).to exist
    end
  end
end
