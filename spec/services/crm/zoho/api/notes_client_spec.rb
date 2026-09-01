require 'rails_helper'

describe Crm::Zoho::Api::NotesClient do
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

  describe '#create' do
    it 'sends Parent_Id as {id:, module: {api_name:}} — Zoho rejects a bare string (INVALID_DATA) ' \
       'and {id: ...} alone (MANDATORY_NOT_FOUND on Parent_Id.module), confirmed live against Deals' do
      stub = stub_request(:post, %r{zohoapis\.com/crm/v7/Notes})
             .with do |request|
               JSON.parse(request.body).dig('data', 0, 'Parent_Id') ==
                 { 'id' => 'deal-123', 'module' => { 'api_name' => 'Deals' } }
             end
             .to_return(status: 200, body: { data: [{ 'code' => 'SUCCESS', 'details' => { 'id' => 'note-1' } }] }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      described_class.new(hook).create(zoho_id: 'deal-123', zoho_module: 'Deals', title: 'Título', content: 'Contenido')

      expect(stub).to have_been_requested
    end

    it 'sends the module under $se_module, title and content as given' do
      stub = stub_request(:post, %r{zohoapis\.com/crm/v7/Notes})
             .with do |request|
               data = JSON.parse(request.body)['data'].first
               data['$se_module'] == 'Leads' && data['Note_Title'] == 'Título' && data['Note_Content'] == 'Contenido'
             end
             .to_return(status: 200, body: { data: [{ 'code' => 'SUCCESS', 'details' => { 'id' => 'note-1' } }] }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      described_class.new(hook).create(zoho_id: 'lead-1', zoho_module: 'Leads', title: 'Título', content: 'Contenido')

      expect(stub).to have_been_requested
    end
  end
end
