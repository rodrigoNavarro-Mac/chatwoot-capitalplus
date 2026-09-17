require 'rails_helper'

describe V2::Reports::RevenueIntelligenceLeadsExportBuilder do
  let(:account) { create(:account) }
  let(:params) { {} }
  let(:builder) { described_class.new(account: account, params: params) }

  describe '#build' do
    it 'includes the basic lead fields, defaulting contestado/calificado/descartado to No' do
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', desarrollo: 'Fuego', campaign_name: 'camp-1', adset_name: 'adset-1',
                                    advert_name: 'advert-1', lead_source: 'Meta Ads', lead_status: 'Contactado',
                                    created_at_source: 3.days.ago, raw_payload: { 'First_Name' => 'Ana', 'Last_Name' => 'Lopez' })

      row = builder.build.first

      expect(row).to include(zoho_lead_id: 'lead-1', nombre: 'Ana Lopez', desarrollo: 'Fuego', campaign: 'camp-1', adset: 'adset-1',
                             advert: 'advert-1', lead_source: 'Meta Ads', estado: 'Contactado', contestado: 'No', calificado: 'No',
                             descartado: 'No', razon_descarte: nil, es_deal: 'No', etapa_deal: nil, ganado: nil,
                             dias_lead_a_deal: nil, dias_deal_activo: nil)
    end

    it 'marks contestado/calificado/descartado as Sí when their timestamps/reason are present' do
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', first_contact_at: 1.day.ago, qualified_at: 1.day.ago,
                                    discard_reason: 'No contestó')

      row = builder.build.first

      expect(row).to include(contestado: 'Sí', calificado: 'Sí', descartado: 'Sí', razon_descarte: 'No contestó')
    end

    it 'fills in deal columns when the lead already has a revenue_deal' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', created_at_source: 10.days.ago)
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', revenue_lead_id: lead.id, stage: 'Cotizado', created_at_source: 4.days.ago)

      row = builder.build.first

      expect(row[:es_deal]).to eq('Sí')
      expect(row[:etapa_deal]).to eq('Cotizado')
      expect(row[:ganado]).to eq('En curso')
      expect(row[:dias_lead_a_deal]).to eq(6)
      expect(row[:dias_deal_activo]).to eq(4)
    end

    it 'reports ganado as Sí/No for won/lost deals' do
      won_lead = account.revenue_leads.create!(zoho_lead_id: 'lead-won')
      account.revenue_deals.create!(zoho_deal_id: 'deal-won', revenue_lead_id: won_lead.id, won: true, stage: 'Cerrado ganado')
      lost_lead = account.revenue_leads.create!(zoho_lead_id: 'lead-lost')
      account.revenue_deals.create!(zoho_deal_id: 'deal-lost', revenue_lead_id: lost_lead.id, lost: true, stage: 'Cerrado perdido')

      rows = builder.build
      expect(rows.find { |r| r[:zoho_lead_id] == 'lead-won' }[:ganado]).to eq('Sí')
      expect(rows.find { |r| r[:zoho_lead_id] == 'lead-lost' }[:ganado]).to eq('No')
    end

    it 'picks the most recently created deal when a lead has more than one' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1')
      account.revenue_deals.create!(zoho_deal_id: 'deal-old', revenue_lead_id: lead.id, stage: 'Etapa vieja', created_at_source: 20.days.ago)
      account.revenue_deals.create!(zoho_deal_id: 'deal-new', revenue_lead_id: lead.id, stage: 'Etapa nueva', created_at_source: 1.day.ago)

      row = builder.build.first

      expect(row[:etapa_deal]).to eq('Etapa nueva')
    end

    it 'collects distinct WhatsApp template names sent to the associated Chatwoot contact' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1')
      contact = create(:contact, account: account)
      account.revenue_contacts.create!(chatwoot_contact_id: contact.id, first_seen_at: Time.current, last_seen_at: Time.current)
      lead.update!(revenue_contact_id: account.revenue_contacts.last.id)
      conversation = create(:conversation, account: account, contact: contact)
      create(:message, account: account, conversation: conversation, message_type: 'outgoing',
                       additional_attributes: { template_params: { name: 'plantilla_bienvenida' } })
      create(:message, account: account, conversation: conversation, message_type: 'outgoing',
                       additional_attributes: { template_params: { name: 'plantilla_seguimiento' } })
      create(:message, account: account, conversation: conversation, message_type: 'outgoing')

      row = builder.build.first

      expect(row[:plantillas_enviadas]).to eq('plantilla_bienvenida, plantilla_seguimiento')
    end

    it 'filters by desarrollo when present in params' do
      account.revenue_leads.create!(zoho_lead_id: 'lead-fuego', desarrollo: 'Fuego')
      account.revenue_leads.create!(zoho_lead_id: 'lead-amura', desarrollo: 'Amura')
      scoped_builder = described_class.new(account: account, params: { desarrollo: 'Fuego' })

      rows = scoped_builder.build

      expect(rows.map { |r| r[:zoho_lead_id] }).to contain_exactly('lead-fuego')
    end

    it 'filters by created_at_source date range when since/until are present in params' do
      account.revenue_leads.create!(zoho_lead_id: 'lead-in-range', created_at_source: 10.days.ago)
      account.revenue_leads.create!(zoho_lead_id: 'lead-out-of-range', created_at_source: 40.days.ago)
      ranged_builder = described_class.new(account: account, params: { since: 20.days.ago.to_i.to_s, until: Time.current.to_i.to_s })

      rows = ranged_builder.build

      expect(rows.map { |r| r[:zoho_lead_id] }).to contain_exactly('lead-in-range')
    end

    it 'includes a lead created outside the range if its deal was created inside the range' do
      old_lead = account.revenue_leads.create!(zoho_lead_id: 'lead-old-converted', created_at_source: 40.days.ago)
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', revenue_lead_id: old_lead.id, created_at_source: 2.days.ago)
      account.revenue_leads.create!(zoho_lead_id: 'lead-old-no-deal', created_at_source: 40.days.ago)
      ranged_builder = described_class.new(account: account, params: { since: 20.days.ago.to_i.to_s, until: Time.current.to_i.to_s })

      rows = ranged_builder.build

      expect(rows.map { |r| r[:zoho_lead_id] }).to contain_exactly('lead-old-converted')
      expect(rows.first[:es_deal]).to eq('Sí')
    end
  end
end
