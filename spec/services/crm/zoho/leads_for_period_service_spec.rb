require 'rails_helper'

describe Crm::Zoho::LeadsForPeriodService do
  let(:account) { create(:account, reporting_timezone: 'America/Mexico_City') }
  let(:range) { DateTime.parse('2026-08-03T00:00:00-06:00')...DateTime.parse('2026-08-10T00:00:00-06:00') }

  before do
    account.enable_features!('crm_integration')
    allow_any_instance_of(Crm::Zoho::TokenRefreshService).to receive(:token).and_return('fake-token') # rubocop:disable RSpec/AnyInstance
  end

  def stub_leads_search(criteria_includes:, page: nil, data: [], more_records: false, status: 200)
    stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/search})
      .with do |request|
        query = CGI.parse(URI(request.uri).query)
        matches_criteria = query['criteria'].first.include?(criteria_includes)
        matches_page = page.nil? || query['page'].first == page.to_s
        matches_criteria && matches_page
      end
      .to_return(status: status, body: { data: data, info: { more_records: more_records } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  describe '#fetch' do
    context 'without a configured Zoho hook' do
      it 'returns an empty array without calling the API' do
        result = described_class.new(account: account, development_key: 'Fuego', range: range).fetch

        expect(result).to eq([])
        expect(WebMock).not_to have_requested(:get, /zohoapis\.com/)
      end
    end

    context 'with a configured Zoho hook' do
      before do
        create(:integrations_hook, account: account, app_id: 'zoho_crm', status: 'enabled',
                                   settings: { client_id: 'x', client_secret: 'y', refresh_token: 'z' })
      end

      it 'returns an empty array when development_key is blank' do
        result = described_class.new(account: account, development_key: nil, range: range).fetch

        expect(result).to eq([])
        expect(WebMock).not_to have_requested(:get, /zohoapis\.com/)
      end

      it 'returns an empty array when range is blank' do
        result = described_class.new(account: account, development_key: 'Fuego', range: nil).fetch

        expect(result).to eq([])
        expect(WebMock).not_to have_requested(:get, /zohoapis\.com/)
      end

      it 'searches by desarrollo and Modified_Time between the range bounds' do
        stub = stub_leads_search(criteria_includes: '(Desarrollo:equals:Fuego)and(Modified_Time:between:',
                                 data: [{ 'id' => 'lead-1', 'Lead_Status' => 'Contacted' }])

        result = described_class.new(account: account, development_key: 'Fuego', range: range).fetch

        expect(result).to eq([{ 'id' => 'lead-1', 'Lead_Status' => 'Contacted' }])
        expect(stub).to have_been_requested
      end

      it 'paginates until more_records is false' do
        stub_leads_search(criteria_includes: 'Desarrollo:equals:Fuego', page: 1,
                          data: [{ 'id' => 'lead-1' }], more_records: true)
        stub_leads_search(criteria_includes: 'Desarrollo:equals:Fuego', page: 2,
                          data: [{ 'id' => 'lead-2' }], more_records: false)

        result = described_class.new(account: account, development_key: 'Fuego', range: range).fetch

        expect(result).to eq([{ 'id' => 'lead-1' }, { 'id' => 'lead-2' }])
      end

      it 'reports the exception and returns an empty array when Zoho responds with an error' do
        stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/search}).to_return(status: 500, body: 'boom')
        allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: nil))

        result = described_class.new(account: account, development_key: 'Fuego', range: range).fetch

        expect(result).to eq([])
        expect(ChatwootExceptionTracker).to have_received(:new)
      end
    end
  end
end
