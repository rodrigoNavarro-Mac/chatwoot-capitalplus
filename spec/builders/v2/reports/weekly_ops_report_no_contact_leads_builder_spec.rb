require 'rails_helper'

describe V2::Reports::WeeklyOpsReportNoContactLeadsBuilder do
  subject(:result) { described_class.new(account: account, params: params).build }

  let(:account) { create(:account) }
  let(:params) { { since: Time.zone.parse('2026-09-01').to_i.to_s, until: Time.zone.parse('2026-10-01').to_i.to_s, desarrollo: 'Fuego' } }

  def create_signal_for(lead, resolved_at: nil, context: { 'hours_since_created' => 48 })
    account.revenue_risk_signals.create!(
      category: 'risk', signal_type: 'lead_no_contact', subject_type: 'RevenueLead', subject_id: lead.id,
      severity: 'high', first_detected_at: Time.current, detected_at: Time.current, resolved_at: resolved_at, context: context
    )
  end

  it 'is empty when development_key or range is blank' do
    expect(described_class.new(account: account, params: { since: params[:since], until: params[:until] }).build)
      .to include(total_count: 0, rows: [])
    expect(described_class.new(account: account, params: { desarrollo: 'Fuego' }).build).to include(total_count: 0, rows: [])
  end

  context 'with a lead that has an open lead_no_contact signal' do
    let(:lead) do
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', desarrollo: 'Fuego', lead_source: 'Facebook Ads', owner_name: 'Eunice Vazquez',
                                    created_at_source: Time.zone.parse('2026-09-05T10:00:00-06:00'),
                                    raw_payload: { 'First_Name' => 'Juan', 'Last_Name' => 'Pérez', 'Phone' => '+525512345678' })
    end

    it 'includes it in the audit, with the signal context and lead details' do
      create_signal_for(lead)

      expect(result[:total_count]).to eq(1)
      row = result[:rows].first
      expect(row).to include(zoho_lead_id: 'lead-1', nombre: 'Juan Pérez', telefono: '+525512345678',
                             fuente: 'Facebook Ads', dueno: 'Eunice Vazquez', horas_sin_contacto: 48)
    end
  end

  context 'with a lead whose signal is already resolved (follow-up happened, or it got discarded)' do
    let(:lead) do
      account.revenue_leads.create!(zoho_lead_id: 'lead-2', desarrollo: 'Fuego',
                                    created_at_source: Time.zone.parse('2026-09-05T10:00:00-06:00'))
    end

    it 'does not include it -- a resolved signal means it no longer needs follow-up' do
      create_signal_for(lead, resolved_at: 1.hour.ago)

      expect(result).to include(total_count: 0, rows: [])
    end
  end

  context 'with a lead outside this desarrollo/period' do
    it 'does not include leads from a different desarrollo' do
      other_lead = account.revenue_leads.create!(zoho_lead_id: 'lead-3', desarrollo: 'Otro',
                                                 created_at_source: Time.zone.parse('2026-09-05T10:00:00-06:00'))
      create_signal_for(other_lead)

      expect(result).to include(total_count: 0, rows: [])
    end

    it 'does not include leads created outside the period' do
      old_lead = account.revenue_leads.create!(zoho_lead_id: 'lead-4', desarrollo: 'Fuego',
                                               created_at_source: Time.zone.parse('2026-08-01T10:00:00-06:00'))
      create_signal_for(old_lead)

      expect(result).to include(total_count: 0, rows: [])
    end
  end

  describe 'paginación' do
    let(:params) do
      { since: Time.zone.parse('2026-09-01').to_i.to_s, until: Time.zone.parse('2026-10-01').to_i.to_s, desarrollo: 'Fuego',
        page: 2, per_page: 1 }
    end

    it 'pagina con page/per_page mientras conserva el total_count real' do
      2.times do |i|
        lead = account.revenue_leads.create!(zoho_lead_id: "lead-many-#{i}", desarrollo: 'Fuego',
                                             created_at_source: Time.zone.parse('2026-09-05T10:00:00-06:00'))
        create_signal_for(lead)
      end

      expect(result).to include(total_count: 2, page: 2, per_page: 1, total_pages: 2)
      expect(result[:rows].size).to eq(1)
    end

    it 'cae en DEFAULT_PER_PAGE cuando no se manda per_page' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-default', desarrollo: 'Fuego',
                                           created_at_source: Time.zone.parse('2026-09-05T10:00:00-06:00'))
      create_signal_for(lead)
      result_default = described_class.new(account: account, params: params.except(:per_page)).build

      expect(result_default[:per_page]).to eq(described_class::DEFAULT_PER_PAGE)
    end
  end
end
