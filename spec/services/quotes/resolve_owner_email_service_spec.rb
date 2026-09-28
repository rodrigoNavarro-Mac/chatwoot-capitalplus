require 'rails_helper'

RSpec.describe Quotes::ResolveOwnerEmailService do
  let(:account) { create(:account) }

  describe 'a quote generated from a Zoho Deal' do
    it 'reads the owner email straight from the saved deal_snapshot, without calling Zoho again' do
      quote = create(:quote, account: account, source_type: 'deal', zoho_deal_id: 'DEAL1',
                             deal_snapshot: { 'Owner' => { 'email' => 'owner@example.com' } })

      expect(Crm::Zoho::Api::DealsClient).not_to receive(:new)
      expect(described_class.call(quote: quote)).to eq('owner@example.com')
    end

    it 'returns nil when the snapshot has no Owner' do
      quote = create(:quote, account: account, source_type: 'deal', zoho_deal_id: 'DEAL1', deal_snapshot: {})

      expect(described_class.call(quote: quote)).to be_nil
    end
  end

  describe 'a quote generated from a Product (no Deal involved)' do
    let(:contact) { create(:contact, account: account) }
    let(:hook) { create(:integrations_hook, :zoho_crm, account: account) }

    it "looks up the contact's linked Zoho deal and asks Zoho for its Owner" do
      contact.update!(additional_attributes: { 'external' => { 'zoho_deal_id' => 'DEAL9' } })
      account.enable_features!('crm_integration')
      hook
      quote = create(:quote, account: account, source_type: 'product', contact: contact)

      deals_client = instance_double(Crm::Zoho::Api::DealsClient)
      allow(Crm::Zoho::Api::DealsClient).to receive(:new).and_return(deals_client)
      allow(deals_client).to receive(:find).with('DEAL9', fields: ['Owner']).and_return('Owner' => { 'email' => 'agente@example.com' })

      expect(described_class.call(quote: quote)).to eq('agente@example.com')
    end

    it 'returns nil when the contact has no Zoho deal linked yet' do
      quote = create(:quote, account: account, source_type: 'product', contact: contact)

      expect(described_class.call(quote: quote)).to be_nil
    end

    it 'returns nil when the quote has no contact at all' do
      quote = create(:quote, account: account, source_type: 'product', contact: nil)

      expect(described_class.call(quote: quote)).to be_nil
    end
  end
end
