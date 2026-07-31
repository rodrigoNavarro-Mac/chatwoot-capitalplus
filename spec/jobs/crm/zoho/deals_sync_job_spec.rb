require 'rails_helper'

describe Crm::Zoho::DealsSyncJob do
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
    hook # crear el hook después de habilitar la feature (create!(...) valida el feature flag)

    # Catch-all: este entorno de test puede tener otros hooks zoho_crm/contactos preexistentes
    # (compartido), y el job los procesa a todos sin filtrar por cuenta. Los stubs específicos
    # de cada test, registrados después, tienen prioridad sobre este catch-all para sus propios
    # números — lo que importa en cada test es el contacto que sí controla, no "cero requests".
    stub_request(:get, %r{zohoapis\.com/crm/v7/Contacts/search}).to_return(status: 204, body: '')
    stub_request(:get, %r{zohoapis\.com/crm/v7/Deals/search}).to_return(status: 204, body: '')
  end

  def stub_zoho_deal(phone:, deal_id:, stage:)
    stub_request(:get, %r{zohoapis\.com/crm/v7/Contacts/search})
      .with { |request| CGI.parse(URI(request.uri).query)['criteria'].first.include?("Phone:equals:#{phone}") }
      .to_return(status: 200, body: { data: [{ 'id' => "zoho-#{phone}" }] }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{zohoapis\.com/crm/v7/Deals/search})
      .with(query: hash_including('criteria' => "(Contact_Name:equals:zoho-#{phone})"))
      .to_return(status: 200, body: { data: [{ 'id' => deal_id, 'Stage' => stage, 'Modified_Time' => '2026-01-01T00:00:00-06:00' }] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  describe '#perform' do
    it 'caches the deal id and stage for a contact matched by phone, even if still marked as a Lead in Chatwoot' do
      contact = create(:contact, account: account, phone_number: '+15551234567',
                                 additional_attributes: { 'external' => { 'zoho_id' => 'lead-1', 'zoho_module' => 'Leads' } })
      stub_zoho_deal(phone: '+15551234567', deal_id: 'deal-1', stage: 'Negotiation/Review')

      described_class.new.perform

      ext = contact.reload.additional_attributes['external']
      expect(ext['zoho_deal_id']).to eq('deal-1')
      expect(ext['zoho_deal_stage']).to eq('Negotiation/Review')
      expect(ext['zoho_deal_synced_at']).to be_present
    end

    it 'does not touch a contact without any Zoho link' do
      contact = create(:contact, account: account, phone_number: '+15551234567')

      described_class.new.perform

      expect(contact.reload.additional_attributes).to eq({})
    end

    it 'leaves the contact untouched when no deal is found for it' do
      contact = create(:contact, account: account, phone_number: '+15551234567',
                                 additional_attributes: { 'external' => { 'zoho_id' => 'lead-1', 'zoho_module' => 'Leads' } })

      described_class.new.perform

      expect(contact.reload.additional_attributes['external']).not_to have_key('zoho_deal_id')
    end

    it 'continues syncing other hooks when one hook raises' do
      other_account = create(:account)
      other_account.enable_features!('crm_integration')
      create(:integrations_hook, :zoho_crm, account: other_account, status: 'enabled')
      other_contact = create(:contact, account: other_account, phone_number: '+15559999999',
                                       additional_attributes: { 'external' => { 'zoho_id' => 'lead-2' } })
      create(:contact, account: account, phone_number: '+15551234567', additional_attributes: { 'external' => { 'zoho_id' => 'lead-1' } })

      allow_any_instance_of(Crm::Zoho::Api::DealsClient).to receive(:deals_for_contacts) # rubocop:disable RSpec/AnyInstance
        .and_wrap_original do |method, contacts|
          raise 'boom' if contacts.any? { |c| c[:phone] == '+15551234567' }

          method.call(contacts)
        end
      stub_zoho_deal(phone: '+15559999999', deal_id: 'deal-2', stage: 'Closed Won')

      expect { described_class.new.perform }.not_to raise_error
      expect(other_contact.reload.additional_attributes.dig('external', 'zoho_deal_id')).to eq('deal-2')
    end

    it 'only syncs the given account when an account_id is passed (manual "sync now" trigger)' do
      other_account = create(:account)
      other_account.enable_features!('crm_integration')
      create(:integrations_hook, :zoho_crm, account: other_account, status: 'enabled')
      other_contact = create(:contact, account: other_account, phone_number: '+15559999999',
                                       additional_attributes: { 'external' => { 'zoho_id' => 'lead-2' } })
      create(:contact, account: account, phone_number: '+15551234567', additional_attributes: { 'external' => { 'zoho_id' => 'lead-1' } })
      stub_zoho_deal(phone: '+15551234567', deal_id: 'deal-1', stage: 'Closed Won')
      stub_zoho_deal(phone: '+15559999999', deal_id: 'deal-2', stage: 'Closed Won')

      described_class.new.perform(account.id)

      expect(other_contact.reload.additional_attributes.dig('external', 'zoho_deal_id')).to be_nil
    end
  end
end
