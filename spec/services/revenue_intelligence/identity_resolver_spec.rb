require 'rails_helper'

describe RevenueIntelligence::IdentityResolver do
  let(:account) { create(:account) }
  let(:resolver) { described_class.new(account) }

  def build_lead(zoho_lead_id:, phone: nil, mobile: nil, email: nil)
    account.revenue_leads.create!(
      zoho_lead_id: zoho_lead_id,
      raw_payload: { 'Phone' => phone, 'Mobile' => mobile, 'Email' => email }.compact
    )
  end

  def build_deal(zoho_deal_id:, zoho_contact_id: nil, revenue_lead: nil)
    account.revenue_deals.create!(
      zoho_deal_id: zoho_deal_id,
      revenue_lead: revenue_lead,
      raw_payload: zoho_contact_id ? { 'Contact_Name' => { 'id' => zoho_contact_id } } : {}
    )
  end

  describe '#resolve_for_lead' do
    it 'creates a new revenue_contact anchored on zoho_lead_id when nothing matches' do
      lead = build_lead(zoho_lead_id: 'lead-1', mobile: '9981234567', email: 'ana@example.com')

      contact = resolver.resolve_for_lead(lead)

      expect(contact).to be_persisted
      expect(contact.zoho_lead_id).to eq('lead-1')
      expect(contact.normalized_phone).to eq('+529981234567')
      expect(contact.raw_phone).to eq('9981234567')
      expect(contact.email).to eq('ana@example.com')
      expect(lead.reload.revenue_contact_id).to eq(contact.id)
    end

    it 'is idempotent — resolving the same lead twice does not create a duplicate contact' do
      lead = build_lead(zoho_lead_id: 'lead-1', mobile: '9981234567')

      first = resolver.resolve_for_lead(lead)
      second = resolver.resolve_for_lead(lead)

      expect(second.id).to eq(first.id)
      expect(RevenueContact.where(account: account).count).to eq(1)
    end

    it 'prefers Mobile over Phone, matching what agents commonly load with the WhatsApp number' do
      lead = build_lead(zoho_lead_id: 'lead-1', phone: '9980000000', mobile: '9981234567')

      contact = resolver.resolve_for_lead(lead)

      expect(contact.raw_phone).to eq('9981234567')
    end

    it 'links chatwoot_contact_id when a Chatwoot contact with the same phone already exists' do
      chatwoot_contact = create(:contact, account: account, phone_number: '+529981234567')
      lead = build_lead(zoho_lead_id: 'lead-1', mobile: '9981234567')

      contact = resolver.resolve_for_lead(lead)

      expect(contact.chatwoot_contact_id).to eq(chatwoot_contact.id)
    end

    it 'links two different leads that share the same phone number to the same revenue_contact' do
      first_lead = build_lead(zoho_lead_id: 'lead-1', mobile: '9981234567')
      resolver.resolve_for_lead(first_lead)

      second_lead = build_lead(zoho_lead_id: 'lead-2', mobile: '9981234567')
      contact = resolver.resolve_for_lead(second_lead)

      expect(contact.id).to eq(first_lead.reload.revenue_contact.id)
      expect(second_lead.reload.revenue_contact_id).to eq(contact.id)
    end

    it 'does not overwrite an existing zoho_lead_id with a different one, and logs a field_mismatch conflict' do
      first_lead = build_lead(zoho_lead_id: 'lead-1', mobile: '9981234567')
      resolver.resolve_for_lead(first_lead)

      duplicate_lead = build_lead(zoho_lead_id: 'lead-2', mobile: '9981234567')
      contact = resolver.resolve_for_lead(duplicate_lead)

      expect(contact.zoho_lead_id).to eq('lead-1') # no se sobrescribe
      conflict = account.revenue_identity_conflicts.last
      expect(conflict.conflict_type).to eq('field_mismatch')
      expect(conflict.candidate_ids).to include(contact.id)
    end

    it 'never fills a non-nil field with a different value from a plain, un-guarded update' do
      lead = build_lead(zoho_lead_id: 'lead-1', mobile: '9981234567', email: 'first@example.com')
      contact = resolver.resolve_for_lead(lead)

      other_lead = build_lead(zoho_lead_id: 'lead-2', mobile: '9981234567', email: 'second@example.com')
      resolver.resolve_for_lead(other_lead)

      expect(contact.reload.email).to eq('first@example.com')
    end

    it 'picks a deterministic primary and logs multiple_candidates when two signals point to different contacts' do
      lead_a = build_lead(zoho_lead_id: 'lead-a', mobile: nil)
      contact_a = resolver.resolve_for_lead(lead_a)
      resolver.resolve_for_lead(build_lead(zoho_lead_id: 'lead-b', mobile: '9989999999'))
      contact_b = RevenueContact.find_by!(account: account, normalized_phone: '+529989999999')

      # El mismo lead A se re-sincroniza con un teléfono nuevo en Zoho que ya coincide con B —
      # su zoho_lead_id sigue apuntando a A, pero ahora su teléfono también apunta a B.
      lead_a.update!(raw_payload: { 'Mobile' => '9989999999' })
      resolved = resolver.resolve_for_lead(lead_a)

      # zoho_lead_id tiene mayor prioridad que teléfono -> gana A.
      expect(resolved.id).to eq(contact_a.id)
      conflict = account.revenue_identity_conflicts.find_by(conflict_type: 'multiple_candidates')
      expect(conflict.candidate_ids).to contain_exactly(contact_a.id, contact_b.id)
    end

    it 'does not create a revenue_contact when the lead has no usable phone/email' do
      lead = build_lead(zoho_lead_id: 'lead-1')

      contact = resolver.resolve_for_lead(lead)

      expect(contact).to be_persisted
      expect(contact.normalized_phone).to be_nil
      expect(contact.raw_phone).to be_nil
    end

    it 'leaves normalized_phone nil for an unparseable phone but preserves the raw value' do
      lead = build_lead(zoho_lead_id: 'lead-1', mobile: 'not-a-phone')

      contact = resolver.resolve_for_lead(lead)

      expect(contact.raw_phone).to eq('not-a-phone')
      expect(contact.normalized_phone).to be_nil
    end
  end

  describe '#resolve_for_deal' do
    it 'reuses the revenue_contact already resolved for the linked revenue_lead, without touching Zoho' do
      lead = build_lead(zoho_lead_id: 'lead-1', mobile: '9981234567')
      lead_contact = resolver.resolve_for_lead(lead)
      deal = build_deal(zoho_deal_id: 'deal-1', revenue_lead: lead)

      contact = resolver.resolve_for_deal(deal)

      expect(contact.id).to eq(lead_contact.id)
      expect(deal.reload.revenue_contact_id).to eq(lead_contact.id)
    end

    it 'falls back to matching by zoho_contact_id (Contact_Name) when there is no linked lead' do
      deal = build_deal(zoho_deal_id: 'deal-1', zoho_contact_id: 'zcontact-1')

      contact = resolver.resolve_for_deal(deal)

      expect(contact.zoho_contact_id).to eq('zcontact-1')
      expect(deal.reload.revenue_contact_id).to eq(contact.id)
    end

    it 'is idempotent for the zoho_contact_id fallback path' do
      first_deal = build_deal(zoho_deal_id: 'deal-1', zoho_contact_id: 'zcontact-1')
      resolver.resolve_for_deal(first_deal)

      second_deal = build_deal(zoho_deal_id: 'deal-2', zoho_contact_id: 'zcontact-1')
      contact = resolver.resolve_for_deal(second_deal)

      expect(RevenueContact.where(account: account).count).to eq(1)
      expect(second_deal.reload.revenue_contact_id).to eq(contact.id)
    end
  end
end
