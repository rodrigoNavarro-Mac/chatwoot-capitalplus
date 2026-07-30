require 'rails_helper'

describe Crm::Zoho::Api::DealsClient do
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

  def stub_contacts_search(records)
    stub_request(:get, %r{zohoapis\.com/crm/v7/Contacts/search})
      .to_return(status: 200, body: { data: records }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_deals_search(records)
    stub_request(:get, %r{zohoapis\.com/crm/v7/Deals/search})
      .to_return(status: 200, body: { data: records }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#deals_for_contacts' do
    it 'resolves the contact in Zoho by phone, then finds the deal linked to that contact id' do
      stub_contacts_search([{ 'id' => 'zoho-contact-1' }])
      deals_stub = stub_deals_search([{ 'id' => 'deal-1', 'Stage' => 'Qualification', 'Modified_Time' => '2026-01-01T00:00:00-06:00' }])

      result = described_class.new(hook).deals_for_contacts([{ id: 1, phone: '+15551234567', email: nil }])

      expect(result).to eq(1 => { deal_id: 'deal-1', stage: 'Qualification', modified_time: '2026-01-01T00:00:00-06:00' })
      expect(deals_stub.with(query: hash_including('criteria' => '(Contact_Name:equals:zoho-contact-1)'))).to have_been_requested
    end

    it 'resolves the contact by email when the contact has no phone' do
      stub_contacts_search([{ 'id' => 'zoho-contact-1' }])
      stub_deals_search([{ 'id' => 'deal-1', 'Stage' => 'Qualification', 'Modified_Time' => '2026-01-01T00:00:00-06:00' }])

      result = described_class.new(hook).deals_for_contacts([{ id: 1, phone: nil, email: 'lead@example.com' }])

      expect(result[1]).to include(deal_id: 'deal-1')
    end

    it 'keeps the most recently modified deal when the contact has more than one' do
      stub_contacts_search([{ 'id' => 'zoho-contact-1' }])
      stub_deals_search([
                          { 'id' => 'deal-old', 'Stage' => 'Qualification', 'Modified_Time' => '2026-01-01T00:00:00-06:00' },
                          { 'id' => 'deal-new', 'Stage' => 'Closed Won', 'Modified_Time' => '2026-02-01T00:00:00-06:00' }
                        ])

      result = described_class.new(hook).deals_for_contacts([{ id: 1, phone: '+15551234567', email: nil }])

      expect(result[1]).to eq(deal_id: 'deal-new', stage: 'Closed Won', modified_time: '2026-02-01T00:00:00-06:00')
    end

    it 'skips the contact when it cannot be resolved to a Zoho Contact (still just a Lead, or not found)' do
      stub_request(:get, %r{zohoapis\.com/crm/v7/Contacts/search}).to_return(status: 204, body: '')

      result = described_class.new(hook).deals_for_contacts([{ id: 1, phone: '+15551234567', email: nil }])

      expect(result).to eq({})
      expect(WebMock).not_to have_requested(:get, %r{zohoapis\.com/crm/v7/Deals/search})
    end

    it 'skips the contact when the resolved Zoho Contact has no deal' do
      stub_contacts_search([{ 'id' => 'zoho-contact-1' }])
      stub_request(:get, %r{zohoapis\.com/crm/v7/Deals/search}).to_return(status: 204, body: '')

      result = described_class.new(hook).deals_for_contacts([{ id: 1, phone: '+15551234567', email: nil }])

      expect(result).to eq({})
    end

    it 'skips contacts without a phone or email without calling the API for them' do
      described_class.new(hook).deals_for_contacts([{ id: 1, phone: nil, email: nil }])

      expect(WebMock).not_to have_requested(:get, %r{zohoapis\.com/crm/v7})
    end

    it 'processes each contact independently' do
      stub_request(:get, %r{zohoapis\.com/crm/v7/Contacts/search})
        .with { |request| CGI.parse(URI(request.uri).query)['criteria'].first.include?('Phone:equals:+15551111111') }
        .to_return(status: 200, body: { data: [{ 'id' => 'zoho-contact-1' }] }.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{zohoapis\.com/crm/v7/Contacts/search})
        .with { |request| CGI.parse(URI(request.uri).query)['criteria'].first.include?('Phone:equals:+15552222222') }
        .to_return(status: 204, body: '')
      stub_deals_search([{ 'id' => 'deal-1', 'Stage' => 'Qualification', 'Modified_Time' => '2026-01-01T00:00:00-06:00' }])

      result = described_class.new(hook).deals_for_contacts([
                                                              { id: 1, phone: '+15551111111', email: nil },
                                                              { id: 2, phone: '+15552222222', email: nil }
                                                            ])

      expect(result.keys).to eq([1])
    end
  end
end
