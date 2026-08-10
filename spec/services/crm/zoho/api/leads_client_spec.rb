require 'rails_helper'

describe Crm::Zoho::Api::LeadsClient do
  let(:account) { create(:account) }
  let(:hook) do
    create(
      :integrations_hook, account: account, app_id: 'zoho_crm', status: 'enabled',
                          settings: { client_id: 'x', client_secret: 'y', refresh_token: 'z' }
    )
  end

  before do
    account.enable_features!('crm_integration')
    allow_any_instance_of(Crm::Zoho::TokenRefreshService).to receive(:token).and_return('fake-token') # rubocop:disable RSpec/AnyInstance
  end

  describe '#search' do
    it 'searches by phone using field criteria, including formats without the "+" and without the country code' do
      stub = stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/search})
             .with { |request| CGI.parse(URI(request.uri).query)['criteria'].first.include?('Phone:equals:+15551234567') }
             .to_return(status: 200, body: { data: [{ 'id' => 'lead-1' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

      records = described_class.new(hook).search(phone: '+15551234567')

      expect(records).to eq([{ 'id' => 'lead-1' }])
      expect(stub).to have_been_requested
    end

    it 'includes the phone number without the "+" as a search variant' do
      stub = stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/search})
             .with { |request| CGI.parse(URI(request.uri).query)['criteria'].first.include?('Phone:equals:15551234567') }
             .to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

      described_class.new(hook).search(phone: '+15551234567')

      expect(stub).to have_been_requested
    end

    it 'also compares the phone variants against the Mobile field' do
      stub = stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/search})
             .with { |request| CGI.parse(URI(request.uri).query)['criteria'].first.include?('Mobile:equals:+15551234567') }
             .to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

      described_class.new(hook).search(phone: '+15551234567')

      expect(stub).to have_been_requested
    end

    it 'searches by email as well when both email and phone are present' do
      stub = stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/search})
             .with { |request| CGI.parse(URI(request.uri).query)['criteria'].first.include?('Email:equals:lead@example.com') }
             .to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

      described_class.new(hook).search(email: 'lead@example.com', phone: '+15551234567')

      expect(stub).to have_been_requested
    end

    it 'returns an empty array when Zoho responds with 204 (no results)' do
      stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/search})
        .to_return(status: 204, body: '')

      expect(described_class.new(hook).search(phone: '+15551234567')).to eq([])
    end

    it 'returns an empty array without calling the API when there is no email or phone' do
      described_class.new(hook).search

      expect(WebMock).not_to have_requested(:get, %r{zohoapis\.com/crm/v7/Leads/search})
    end
  end

  describe '#search_by_criteria' do
    it 'sends the given criteria, page and per_page, and returns data with more_records' do
      stub = stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/search})
             .with do |request|
               query = CGI.parse(URI(request.uri).query)
               query['criteria'].first == '(Desarrollo:equals:Fuego)' && query['page'].first == '2' && query['per_page'].first == '50'
             end
             .to_return(
               status: 200,
               body: { data: [{ 'id' => 'lead-1' }], info: { more_records: true } }.to_json,
               headers: { 'Content-Type' => 'application/json' }
             )

      result = described_class.new(hook).search_by_criteria('(Desarrollo:equals:Fuego)', page: 2, per_page: 50)

      expect(result).to eq(data: [{ 'id' => 'lead-1' }], more_records: true)
      expect(stub).to have_been_requested
    end

    it 'returns an empty result without raising when Zoho responds with 204 (no results)' do
      stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/search}).to_return(status: 204, body: '')

      result = described_class.new(hook).search_by_criteria('(Desarrollo:equals:Fuego)')

      expect(result).to eq(data: [], more_records: false)
    end
  end
end
