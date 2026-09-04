require 'rails_helper'

describe RevenueIntelligence::Zoho::StageHistoryClient do
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

  describe '#list' do
    it 'requests the Stage_History related list of the given deal with the expected fields' do
      stub = stub_request(:get, %r{zohoapis\.com/crm/v7/Deals/deal-1/Stage_History})
             .with { |request| CGI.parse(URI(request.uri).query)['fields'].first == described_class::FIELDS.join(',') }
             .to_return(
               status: 200,
               body: { data: [{ 'id' => 'hist-1', 'Stage' => 'Apartado' }] }.to_json,
               headers: { 'Content-Type' => 'application/json' }
             )

      records = described_class.new(hook).list('deal-1')

      expect(records).to eq([{ 'id' => 'hist-1', 'Stage' => 'Apartado' }])
      expect(stub).to have_been_requested
    end

    it 'returns an empty array when Zoho responds with 204 (no history yet)' do
      stub_request(:get, %r{zohoapis\.com/crm/v7/Deals/deal-1/Stage_History}).to_return(status: 204, body: '')

      expect(described_class.new(hook).list('deal-1')).to eq([])
    end

    it 're-raises other API errors instead of swallowing them' do
      stub_request(:get, %r{zohoapis\.com/crm/v7/Deals/deal-1/Stage_History}).to_return(status: 500, body: 'boom')

      expect { described_class.new(hook).list('deal-1') }.to raise_error(Crm::Zoho::Api::BaseClient::ApiError)
    end
  end
end
