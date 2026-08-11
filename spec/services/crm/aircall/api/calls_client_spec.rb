require 'rails_helper'

describe Crm::Aircall::Api::CallsClient do
  let(:account) { create(:account) }
  let(:hook) do
    create(:integrations_hook, account: account, app_id: 'aircall', status: 'enabled',
                               settings: { webhook_secret: 'x', api_id: 'my-api-id', api_token: 'my-api-token' })
  end
  let(:from) { Time.zone.parse('2026-07-01T00:00:00Z') }
  let(:to) { Time.zone.parse('2026-07-31T23:59:59Z') }

  describe '#list' do
    it 'authenticates with basic auth using the hook\'s api_id/api_token' do
      stub = stub_request(:get, %r{api\.aircall\.io/v1/calls})
             .with(basic_auth: %w[my-api-id my-api-token])
             .to_return(status: 200, body: { calls: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

      described_class.new(hook).list(from: from, to: to)

      expect(stub).to have_been_requested
    end

    it 'sends from/to as unix timestamps along with page, per_page and order' do
      stub = stub_request(:get, %r{api\.aircall\.io/v1/calls})
             .with do |request|
               query = CGI.parse(URI(request.uri).query)
               query['from'].first == from.to_i.to_s &&
                 query['to'].first == to.to_i.to_s &&
                 query['page'].first == '2' &&
                 query['per_page'].first == '50' &&
                 query['order'].first == 'asc'
             end
             .to_return(status: 200, body: { calls: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

      described_class.new(hook).list(from: from, to: to, page: 2)

      expect(stub).to have_been_requested
    end

    it 'returns the parsed response body' do
      stub_request(:get, %r{api\.aircall\.io/v1/calls})
        .to_return(status: 200, body: { calls: [{ 'id' => 1 }], meta: { total: 1 } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = described_class.new(hook).list(from: from, to: to)

      expect(result).to eq('calls' => [{ 'id' => 1 }], 'meta' => { 'total' => 1 })
    end

    it 'raises ApiError when Aircall responds with an error status' do
      stub_request(:get, %r{api\.aircall\.io/v1/calls})
        .to_return(status: 401, body: 'Unauthorized')

      expect { described_class.new(hook).list(from: from, to: to) }
        .to raise_error(Crm::Aircall::Api::CallsClient::ApiError, /401/)
    end
  end
end
