require 'rails_helper'

describe Crm::Zoho::DealsSyncJob do
  let(:account) { create(:account) }

  before do
    account.enable_features!('crm_integration')
    allow_any_instance_of(Crm::Zoho::TokenRefreshService).to receive(:token).and_return('fake-token') # rubocop:disable RSpec/AnyInstance
  end

  let!(:hook) do
    create(
      :integrations_hook, account: account, app_id: 'zoho_crm', status: 'enabled',
                          settings: { client_id: 'x', client_secret: 'y', refresh_token: 'z' }
    )
  end

  def stub_coql(rows)
    stub_request(:post, %r{zohoapis\.com/crm/v7/coql})
      .to_return(status: 200, body: { data: rows }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#perform' do
    it 'caches the deal id and stage for a contact already converted to a Zoho Contact' do
      contact = create(:contact, account: account,
                                  additional_attributes: { 'external' => { 'zoho_id' => 'contact-1', 'zoho_module' => 'Contacts' } })
      stub_coql([{ 'id' => 'deal-1', 'Stage' => 'Negotiation/Review', 'Contact_Name' => { 'id' => 'contact-1' },
                   'Modified_Time' => '2026-01-01T00:00:00-06:00' }])

      described_class.new.perform

      ext = contact.reload.additional_attributes['external']
      expect(ext['zoho_deal_id']).to eq('deal-1')
      expect(ext['zoho_deal_stage']).to eq('Negotiation/Review')
      expect(ext['zoho_deal_synced_at']).to be_present
    end

    it 'does not query Zoho for contacts still at the Lead stage (not yet converted to Contact)' do
      create(:contact, account: account, additional_attributes: { 'external' => { 'zoho_id' => 'lead-1', 'zoho_module' => 'Leads' } })

      described_class.new.perform

      expect(WebMock).not_to have_requested(:post, %r{zohoapis\.com/crm/v7/coql})
    end

    it 'leaves the contact untouched when no deal is found for it' do
      contact = create(:contact, account: account,
                                  additional_attributes: { 'external' => { 'zoho_id' => 'contact-1', 'zoho_module' => 'Contacts' } })
      stub_coql([])

      described_class.new.perform

      expect(contact.reload.additional_attributes['external']).not_to have_key('zoho_deal_id')
    end

    it 'continues syncing other hooks when one hook raises' do
      other_account = create(:account)
      other_account.enable_features!('crm_integration')
      create(:integrations_hook, :zoho_crm, account: other_account, status: 'enabled')
      contact = create(:contact, account: other_account,
                                  additional_attributes: { 'external' => { 'zoho_id' => 'contact-2', 'zoho_module' => 'Contacts' } })
      create(:contact, account: account, additional_attributes: { 'external' => { 'zoho_id' => 'contact-1', 'zoho_module' => 'Contacts' } })

      allow_any_instance_of(Crm::Zoho::Api::DealsClient).to receive(:deals_by_contact_ids) # rubocop:disable RSpec/AnyInstance
        .and_wrap_original do |method, contact_ids|
          raise 'boom' if contact_ids.include?('contact-1')

          method.call(contact_ids)
        end
      stub_coql([{ 'id' => 'deal-2', 'Stage' => 'Closed Won', 'Contact_Name' => { 'id' => 'contact-2' },
                   'Modified_Time' => '2026-01-01T00:00:00-06:00' }])

      expect { described_class.new.perform }.not_to raise_error
      expect(contact.reload.additional_attributes.dig('external', 'zoho_deal_id')).to eq('deal-2')
    end
  end
end
