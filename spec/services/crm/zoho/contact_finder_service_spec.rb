require 'rails_helper'

describe Crm::Zoho::ContactFinderService do
  subject(:finder) { described_class.new(hook) }

  let(:account) { create(:account) }
  let(:hook) { create(:integrations_hook, :zoho_crm, account: account) }
  let(:contact) { create(:contact, account: account, email: 'lead@example.com', phone_number: '+525512345678') }

  before do
    account.enable_features!('crm_integration')
    allow_any_instance_of(Crm::Zoho::TokenRefreshService).to receive(:token).and_return('fake-token') # rubocop:disable RSpec/AnyInstance
    stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/search}).to_return(status: 204, body: '')
    stub_request(:get, %r{zohoapis\.com/crm/v7/Contacts/search}).to_return(status: 204, body: '')
  end

  # Bug real encontrado en producción 2026-10-07: un lead creado en Zoho desde Chatwoot sin
  # Desarrollo queda invisible para Revenue Intelligence y para el export de leads/deals del
  # reporte semanal (ambos filtran por ese campo), aunque Chatwoot sí sepa de qué inbox vino --
  # la causa de que "Leads totales" (embudo de Chatwoot) y "Leads nuevos" (Zoho) no coincidieran.
  describe '#find_or_create' do
    context 'when a development_key is given (el caller tiene un inbox en contexto)' do
      it 'sends Desarrollo when creating the lead in Zoho' do
        stub = stub_request(:post, %r{zohoapis\.com/crm/v7/Leads})
               .with { |request| JSON.parse(request.body).dig('data', 0, 'Desarrollo') == 'Fuego' }
               .to_return(status: 201, body: { data: [{ details: { id: 'new-lead-1' } }] }.to_json,
                          headers: { 'Content-Type' => 'application/json' })

        result = finder.find_or_create(contact, development_key: 'Fuego')

        expect(result[:zoho_id]).to eq('new-lead-1')
        expect(stub).to have_been_requested
      end
    end

    context 'when no development_key is given (ej. handle_contact sin conversación todavía)' do
      it 'creates the lead without a Desarrollo field, same as before this fix' do
        stub = stub_request(:post, %r{zohoapis\.com/crm/v7/Leads})
               .with { |request| !JSON.parse(request.body)['data'].first.key?('Desarrollo') }
               .to_return(status: 201, body: { data: [{ details: { id: 'new-lead-2' } }] }.to_json,
                          headers: { 'Content-Type' => 'application/json' })

        result = finder.find_or_create(contact)

        expect(result[:zoho_id]).to eq('new-lead-2')
        expect(stub).to have_been_requested
      end
    end

    context 'when the contact already has a stored zoho_id' do
      before { contact.update!(additional_attributes: { 'external' => { 'zoho_id' => 'existing-1', 'zoho_module' => 'Leads' } }) }

      it 'returns the stored data without calling Zoho at all' do
        result = finder.find_or_create(contact, development_key: 'Fuego')

        expect(result[:zoho_id]).to eq('existing-1')
        expect(WebMock).not_to have_requested(:post, /zohoapis\.com/)
      end
    end
  end
end
