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

  def stub_coql(rows)
    stub_request(:post, %r{zohoapis\.com/crm/v7/coql})
      .to_return(status: 200, body: { data: rows }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#deals_by_contact_ids' do
    it 'maps each zoho contact id to its deal id and stage' do
      stub_coql([
                  { 'id' => 'deal-1', 'Stage' => 'Qualification', 'Contact_Name' => { 'id' => 'contact-1' }, 'Modified_Time' => '2026-01-01T00:00:00-06:00' }
                ])

      result = described_class.new(hook).deals_by_contact_ids(['contact-1'])

      expect(result).to eq('contact-1' => { deal_id: 'deal-1', stage: 'Qualification', modified_time: '2026-01-01T00:00:00-06:00' })
    end

    it 'keeps the most recently modified deal when a contact has more than one' do
      stub_coql([
                  { 'id' => 'deal-old', 'Stage' => 'Qualification', 'Contact_Name' => { 'id' => 'contact-1' },
                    'Modified_Time' => '2026-01-01T00:00:00-06:00' },
                  { 'id' => 'deal-new', 'Stage' => 'Closed Won', 'Contact_Name' => { 'id' => 'contact-1' },
                    'Modified_Time' => '2026-02-01T00:00:00-06:00' }
                ])

      result = described_class.new(hook).deals_by_contact_ids(['contact-1'])

      expect(result['contact-1']).to eq(deal_id: 'deal-new', stage: 'Closed Won', modified_time: '2026-02-01T00:00:00-06:00')
    end

    it 'ignores rows without a linked Contact_Name' do
      stub_coql([{ 'id' => 'deal-1', 'Stage' => 'Qualification', 'Contact_Name' => nil, 'Modified_Time' => '2026-01-01T00:00:00-06:00' }])

      expect(described_class.new(hook).deals_by_contact_ids(['contact-1'])).to eq({})
    end

    it 'splits contact ids into batches of CONTACT_BATCH_SIZE, issuing one request per batch' do
      contact_ids = (1..150).map { |i| "contact-#{i}" }
      requests = []
      stub_request(:post, %r{zohoapis\.com/crm/v7/coql}).to_return do |request|
        requests << request
        { status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' } }
      end

      described_class.new(hook).deals_by_contact_ids(contact_ids)

      expect(requests.size).to eq(2)
    end

    it 'returns an empty hash when Zoho responds with 204 (no results)' do
      stub_request(:post, %r{zohoapis\.com/crm/v7/coql}).to_return(status: 204, body: '')

      expect(described_class.new(hook).deals_by_contact_ids(['contact-1'])).to eq({})
    end

    it 'returns an empty hash without calling the API when there are no contact ids' do
      described_class.new(hook).deals_by_contact_ids([])

      expect(WebMock).not_to have_requested(:post, %r{zohoapis\.com/crm/v7/coql})
    end
  end
end
