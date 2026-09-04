require 'rails_helper'

describe RevenueIntelligence::ResolveIdentityJob do
  let(:account) { create(:account) }

  before do
    account.enable_features!('crm_integration')
    create(:integrations_hook, :zoho_crm, account: account, status: 'enabled')
  end

  describe '#perform' do
    it 'resolves the revenue_contact_id of unresolved leads' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', raw_payload: { 'Mobile' => '9981234567' })

      described_class.new.perform

      expect(lead.reload.revenue_contact_id).to be_present
    end

    it 'resolves the revenue_contact_id of unresolved deals via their linked lead' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', raw_payload: { 'Mobile' => '9981234567' })
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', revenue_lead_id: lead.id)

      described_class.new.perform

      expect(deal.reload.revenue_contact_id).to eq(lead.reload.revenue_contact_id)
    end

    it 'does not touch leads/deals that already have a revenue_contact_id' do
      contact = account.revenue_contacts.create!(first_seen_at: Time.current, last_seen_at: Time.current)
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', revenue_contact_id: contact.id)

      expect { described_class.new.perform }.not_to(change { lead.reload.revenue_contact_id })
    end

    it 'is idempotent — running it twice does not create extra revenue_contacts' do
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', raw_payload: { 'Mobile' => '9981234567' })

      described_class.new.perform
      described_class.new.perform

      expect(RevenueContact.where(account: account).count).to eq(1)
    end

    it 'continues with other leads/deals when resolving one of them raises' do
      allow_any_instance_of(RevenueIntelligence::IdentityResolver).to receive(:resolve_for_lead) # rubocop:disable RSpec/AnyInstance
        .and_wrap_original do |method, lead|
          raise 'boom' if lead.zoho_lead_id == 'lead-broken'

          method.call(lead)
        end
      account.revenue_leads.create!(zoho_lead_id: 'lead-broken')
      ok_lead = account.revenue_leads.create!(zoho_lead_id: 'lead-ok', raw_payload: { 'Mobile' => '9981234567' })

      expect { described_class.new.perform }.not_to raise_error
      expect(ok_lead.reload.revenue_contact_id).to be_present
    end

    it 'only resolves the given account when an account_id is passed' do
      other_account = create(:account)
      other_account.enable_features!('crm_integration')
      create(:integrations_hook, :zoho_crm, account: other_account, status: 'enabled')
      other_lead = other_account.revenue_leads.create!(zoho_lead_id: 'lead-other', raw_payload: { 'Mobile' => '9981234567' })
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', raw_payload: { 'Mobile' => '9981234567' })

      described_class.new.perform(account.id)

      expect(other_lead.reload.revenue_contact_id).to be_nil
    end
  end
end
