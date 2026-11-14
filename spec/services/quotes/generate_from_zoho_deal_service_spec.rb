require 'rails_helper'

describe Quotes::GenerateFromZohoDealService do
  let(:account) { create(:account) }
  let(:deals_client) { instance_double(Crm::Zoho::Api::DealsClient) }
  let(:deal) { { 'Deal_Name' => 'Juan - L1', 'Desarollo' => 'Fuego', 'Plazos' => '12', 'Interes' => '8' } }

  before do
    account.enable_features!('crm_integration')
    create(:integrations_hook, account: account, app_id: 'zoho_crm', status: 'enabled',
                               settings: { client_id: 'x', client_secret: 'y', refresh_token: 'z' })
    allow(Crm::Zoho::Api::DealsClient).to receive(:new).and_return(deals_client)
    allow(deals_client).to receive(:find).and_return(deal)
    allow(Quotes::CalculateAndAttachService).to receive(:call)
  end

  def generate
    described_class.call(account: account, zoho_deal_id: 'd1', trigger_source: 'zoho_webhook')
  end

  it 'ignores the Deal interest and uses the rate configured for the development' do
    create(:quote_development_rule, account: account, desarrollo: 'Fuego', interes_default: 12)

    generate

    expect(Quotes::CalculateAndAttachService).to have_received(:call).with(
      quote: an_instance_of(Quote), payload: hash_including('Interes' => '12.0')
    )
  end

  it 'keeps the Deal interest when the development has no configured rate' do
    generate

    expect(Quotes::CalculateAndAttachService).to have_received(:call).with(
      quote: an_instance_of(Quote), payload: hash_including('Interes' => '8')
    )
  end
end
