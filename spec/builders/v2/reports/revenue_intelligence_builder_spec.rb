require 'rails_helper'

describe V2::Reports::RevenueIntelligenceBuilder do
  let(:account) { create(:account) }
  let(:params) { { since: 20.days.ago.to_i.to_s, until: Time.current.to_i.to_s } }
  let(:builder) { described_class.new(account: account, params: params) }

  # rubocop:disable Metrics/ParameterLists
  def rollup(dimension_type, dimension_id, metric, count: 1, sum_value: 0, date: 5.days.ago.to_date, desarrollo: '_all')
    account.revenue_rollups.create!(date: date, dimension_type: dimension_type, dimension_id: dimension_id, metric: metric, count: count,
                                    sum_value: sum_value, desarrollo: desarrollo)
  end
  # rubocop:enable Metrics/ParameterLists

  describe 'desarrollo filter (selector global)' do
    let(:params) { { since: 20.days.ago.to_i.to_s, until: Time.current.to_i.to_s, desarrollo: 'Fuego' } }

    it 'restricts every rollup-backed section to the selected desarrollo when present in params' do
      rollup('funnel', 'Fuego', 'lead_created', count: 3, desarrollo: 'Fuego')
      rollup('funnel', 'OtroDesarrollo', 'lead_created', count: 10, desarrollo: 'OtroDesarrollo')
      rollup('agent', '42', 'call_started', count: 5, desarrollo: 'Fuego')
      rollup('agent', '42', 'call_started', count: 7, desarrollo: 'OtroDesarrollo')

      result = builder.build

      expect(result[:funnel]).to eq({ 'Fuego' => { 'lead_created' => 3 } })
      expect(result[:agent]['42']['call_started']).to eq(5)
    end

    it 'ignores the filter and sums across all desarrollos when desarrollo is absent from params' do
      rollup('funnel', 'Fuego', 'lead_created', count: 3, desarrollo: 'Fuego')
      rollup('funnel', 'OtroDesarrollo', 'lead_created', count: 10, desarrollo: 'OtroDesarrollo')
      unfiltered_builder = described_class.new(account: account, params: { since: 20.days.ago.to_i.to_s, until: Time.current.to_i.to_s })

      result = unfiltered_builder.build

      expect(result[:funnel].values.sum { |m| m['lead_created'] }).to eq(13)
    end

    it 'lists distinct real desarrollos for the selector, excluding the internal "_all" fallback' do
      rollup('funnel', 'Fuego', 'lead_created', desarrollo: 'Fuego')
      rollup('agent', '42', 'call_started', desarrollo: 'OtroDesarrollo')
      rollup('funnel', '_all', 'lead_created', desarrollo: '_all')

      result = builder.build

      expect(result[:available_desarrollos]).to contain_exactly('Fuego', 'OtroDesarrollo')
    end

    it 'echoes back the applied filter as desarrollo_filter' do
      result = builder.build

      expect(result[:desarrollo_filter]).to eq('Fuego')
    end
  end

  describe '#build' do
    it 'sums funnel rollups by dimension_id and metric within the date range' do
      rollup('funnel', 'Fuego', 'lead_created', count: 3)
      rollup('funnel', 'Fuego', 'lead_created', count: 2, date: 6.days.ago.to_date)
      rollup('funnel', 'Fuego', 'closed_won', count: 1)
      rollup('funnel', 'Fuego', 'lead_created', count: 100, date: 60.days.ago.to_date) # fuera del rango

      result = builder.build

      expect(result[:funnel]).to eq({ 'Fuego' => { 'lead_created' => 5, 'closed_won' => 1 } })
    end

    it "does not leak the next day's rollups into range because of UTC vs local timezone " \
       'conversion (confirmado en producción: "agosto" incluía rollups del 1 de septiembre)' do
      mexico = Time.find_zone!('America/Mexico_City')
      params_local = { since: mexico.parse('2026-08-01 00:00:00').to_i.to_s, until: mexico.parse('2026-08-31 23:59:59').to_i.to_s }
      local_builder = described_class.new(account: account, params: params_local)
      rollup('funnel', 'Fuego', 'lead_created', count: 5, date: Date.new(2026, 8, 31))
      rollup('funnel', 'Fuego', 'lead_created', count: 3, date: Date.new(2026, 9, 1))

      result = local_builder.build

      expect(result[:funnel]['Fuego']['lead_created']).to eq(5)
    end

    it 'computes avg_duration_days from sum_value/count of the duration_seconds metric per stage' do
      rollup('pipeline_stage', 'Apartado', 'entered', count: 3)
      rollup('pipeline_stage', 'Apartado', 'duration_seconds', count: 2, sum_value: 4.days.to_i)

      result = builder.build

      expect(result[:pipeline_stage]['Apartado']).to eq({ 'entered' => 3, 'avg_duration_days' => 2.0 })
    end

    it 'leaves avg_duration_days nil for a stage with no closed rows yet' do
      rollup('pipeline_stage', 'Apartado', 'entered', count: 1)

      result = builder.build

      expect(result[:pipeline_stage]['Apartado']).to eq({ 'entered' => 1, 'avg_duration_days' => nil })
    end

    it 'computes avg_score/cta_rate per agent from calls_scored/score_sum/cta_used_count rollups' do
      rollup('agent', '42', 'call_started', count: 5)
      rollup('agent', '42', 'call_answered', count: 3)
      rollup('agent', '42', 'calls_scored', count: 2)
      rollup('agent', '42', 'score_sum', count: 0, sum_value: 150.0)
      rollup('agent', '42', 'cta_used_count', count: 1)

      result = builder.build

      expect(result[:agent]['42']).to eq({ 'call_started' => 5, 'call_answered' => 3, 'call_missed' => 0, 'calls_scored' => 2,
                                           'avg_score' => 75.0, 'cta_rate' => 0.5 })
    end

    it 'leaves avg_score/cta_rate nil for an agent with call activity but no scored calls yet' do
      rollup('agent', '42', 'call_started', count: 1)

      result = builder.build

      expect(result[:agent]['42']).to eq({ 'call_started' => 1, 'call_answered' => 0, 'call_missed' => 0, 'calls_scored' => 0,
                                           'avg_score' => nil, 'cta_rate' => nil })
    end

    it 'builds a campaign -> adset -> advert hierarchy from 3 flat rollup dimensions' do
      rollup('campaign', 'camp-1', 'lead_created', count: 10)
      rollup('adset', 'camp-1::adset-1::Adset Uno', 'lead_created', count: 6)
      rollup('advert', 'camp-1::adset-1::ad-1::Anuncio Uno', 'lead_created', count: 4)

      result = builder.build

      campaign = result[:campaign].find { |c| c[:id] == 'camp-1' }
      expect(campaign[:metrics]).to eq({ 'lead_created' => 10, :lead_contacted_seguimiento => 0 })
      adset = campaign[:adsets].first
      expect(adset).to include(id: 'adset-1', name: 'Adset Uno', metrics: { 'lead_created' => 6, :lead_contacted_seguimiento => 0 })
      expect(adset[:adverts].first).to eq({ id: 'ad-1', name: 'Anuncio Uno',
                                            metrics: { 'lead_created' => 4, :lead_contacted_seguimiento => 0 } })
    end

    it 'counts a lead as "seguimiento" in the Marketing tab when contacted in-range but created before it' do
      rollup('campaign', 'camp-1', 'lead_contacted', count: 1)
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', campaign_id: 'camp-1', created_at_source: 40.days.ago,
                                    first_contact_at: 5.days.ago)

      result = builder.build

      campaign = result[:campaign].find { |c| c[:id] == 'camp-1' }
      expect(campaign[:metrics][:lead_contacted_seguimiento]).to eq(1)
    end

    it 'does not count a lead as "seguimiento" in the Marketing tab when created within the selected range' do
      rollup('campaign', 'camp-1', 'lead_contacted', count: 1)
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', campaign_id: 'camp-1', created_at_source: 5.days.ago,
                                    first_contact_at: 5.days.ago)

      result = builder.build

      campaign = result[:campaign].find { |c| c[:id] == 'camp-1' }
      expect(campaign[:metrics][:lead_contacted_seguimiento]).to eq(0)
    end

    it 'lists marketing_sources (bucket de respaldo para leads sin campaign_id) as a flat list' do
      rollup('lead_source', 'Facebook Ads', 'lead_created', count: 20)
      rollup('lead_source', 'Facebook Ads', 'lead_contacted', count: 15)
      rollup('lead_source', 'Sin fuente', 'lead_created', count: 4)

      result = builder.build

      facebook = result[:marketing_sources].find { |s| s[:id] == 'Facebook Ads' }
      expect(facebook[:metrics]).to eq({ 'lead_created' => 20, 'lead_contacted' => 15, :lead_contacted_seguimiento => 0 })
      expect(result[:marketing_sources].find { |s| s[:id] == 'Sin fuente' }).to be_present
    end

    it 'counts a lead as "seguimiento" in marketing_sources too, same rule as marketing campaigns' do
      rollup('lead_source', 'Facebook Ads', 'lead_contacted', count: 1)
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', lead_source: 'Facebook Ads', created_at_source: 40.days.ago,
                                    first_contact_at: 5.days.ago)

      result = builder.build

      facebook = result[:marketing_sources].find { |s| s[:id] == 'Facebook Ads' }
      expect(facebook[:metrics][:lead_contacted_seguimiento]).to eq(1)
    end

    it 'sums marketing_totals across campaign (top-level only) and lead_source' do
      rollup('campaign', 'camp-1', 'lead_created', count: 10)
      rollup('campaign', 'camp-1', 'lead_contacted', count: 8)
      rollup('adset', 'camp-1::adset-1::Adset 1', 'lead_created', count: 10)
      rollup('lead_source', 'Facebook Ads', 'lead_created', count: 5)
      rollup('lead_source', 'Facebook Ads', 'deal_created', count: 2)
      rollup('lead_source', 'Facebook Ads', 'closed_won', count: 1)

      result = builder.build

      expect(result[:marketing_totals]).to eq(
        { 'lead_created' => 15, 'lead_contacted' => 8, 'lead_converted' => 0, 'deal_created' => 2, 'closed_won' => 1,
          'lead_contacted_seguimiento' => 0 }
      )
    end

    it 'includes seguimiento leads from both campaign and lead_source in marketing_totals' do
      rollup('campaign', 'camp-1', 'lead_contacted', count: 1)
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', campaign_id: 'camp-1', created_at_source: 40.days.ago, first_contact_at: 5.days.ago)
      rollup('lead_source', 'Facebook Ads', 'lead_contacted', count: 1)
      account.revenue_leads.create!(zoho_lead_id: 'lead-2', lead_source: 'Facebook Ads', created_at_source: 40.days.ago,
                                    first_contact_at: 5.days.ago)

      result = builder.build

      expect(result[:marketing_totals]['lead_contacted_seguimiento']).to eq(2)
    end

    it 'leaves adsets empty for a campaign with no adset-level rollups' do
      rollup('campaign', 'camp-2', 'lead_created', count: 3)

      result = builder.build

      campaign = result[:campaign].find { |c| c[:id] == 'camp-2' }
      expect(campaign[:adsets]).to eq([])
    end

    it 'computes a conversion rate from total/converted rollups' do
      rollup('call_conversion', 'cta_used:true', 'total', count: 10)
      rollup('call_conversion', 'cta_used:true', 'converted', count: 4)

      result = builder.build

      expect(result[:call_conversion]['cta_used:true']).to eq({ 'total' => 10, 'converted' => 4, 'rate' => 0.4 })
    end

    it 'defaults rate to 0.0 when there is no total yet' do
      rollup('objection_conversion', 'financiera', 'converted', count: 1)

      result = builder.build

      expect(result[:objection_conversion]['financiera']['rate']).to eq(0.0)
    end

    it 'includes open risk signals grouped by category, regardless of the date filter' do
      account.revenue_risk_signals.create!(category: 'risk', signal_type: 'deal_stalled', subject_type: 'RevenueDeal', subject_id: 1,
                                           severity: 'high', first_detected_at: 90.days.ago, detected_at: 90.days.ago,
                                           context: { 'days_stalled' => 40 })
      account.revenue_risk_signals.create!(category: 'data_quality', signal_type: 'deal_without_lead', subject_type: 'RevenueDeal',
                                           subject_id: 2, first_detected_at: Time.current, detected_at: Time.current)
      account.revenue_risk_signals.create!(category: 'risk', signal_type: 'lead_no_contact', subject_type: 'RevenueLead', subject_id: 1,
                                           first_detected_at: Time.current, detected_at: Time.current, resolved_at: Time.current)

      result = builder.build

      expect(result[:risk_signals][:open].size).to eq(2) # la resuelta no aparece, aunque esté "fuera de rango" tampoco importaría
      expect(result[:risk_signals][:by_category]).to eq({ 'risk' => 1, 'data_quality' => 1 })
      expect(result[:risk_signals][:open].first['context']).to be_a(Hash)
    end

    it 'caps open signals per signal_type (not per category) so a numerous type does not crowd out a rarer one' do
      35.times do |i|
        account.revenue_risk_signals.create!(category: 'risk', signal_type: 'lead_no_contact', subject_type: 'RevenueLead', subject_id: i,
                                             first_detected_at: Time.current, detected_at: Time.current)
      end
      account.revenue_risk_signals.create!(category: 'data_quality', signal_type: 'deal_without_lead', subject_type: 'RevenueDeal',
                                           subject_id: 1, first_detected_at: Time.current, detected_at: Time.current)

      result = builder.build

      open = result[:risk_signals][:open]
      expect(open.count { |s| s['category'] == 'risk' }).to eq(15)
      expect(open.count { |s| s['category'] == 'data_quality' }).to eq(1)
      expect(result[:risk_signals][:by_category]).to eq({ 'risk' => 35, 'data_quality' => 1 })
    end

    it 'does not let many signals of ONE type within the same category crowd out a rarer type of the same category' do
      # Bug real (2026-09-08): unresolved_identity_conflict (severidad 'medium', numerosos tras un
      # backfill) ocultaba por completo a deal_without_lead (severidad 'low') dentro de
      # 'data_quality' bajo un tope global por categoría — nunca aparecía ni la fila ni el botón
      # de acción correspondiente.
      25.times do |i|
        account.revenue_risk_signals.create!(category: 'data_quality', signal_type: 'unresolved_identity_conflict', severity: 'medium',
                                             subject_type: 'RevenueIdentityConflict', subject_id: i,
                                             first_detected_at: Time.current, detected_at: Time.current)
      end
      account.revenue_risk_signals.create!(category: 'data_quality', signal_type: 'deal_without_lead', severity: 'low',
                                           subject_type: 'RevenueDeal', subject_id: 1,
                                           first_detected_at: Time.current, detected_at: Time.current)

      result = builder.build

      types = result[:risk_signals][:open].map { |s| s['signal_type'] }
      expect(types).to include('deal_without_lead')
      expect(types.count('unresolved_identity_conflict')).to eq(15)
    end

    it 'resolves a real subject_label for RevenueLead/RevenueDeal signals from raw_payload, instead of a raw "Model #id"' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', raw_payload: { 'First_Name' => 'Ana', 'Last_Name' => 'Pérez' })
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', raw_payload: { 'Deal_Name' => 'Ana Pérez - Depto 302' })
      account.revenue_risk_signals.create!(category: 'risk', signal_type: 'lead_no_contact', subject_type: 'RevenueLead', subject_id: lead.id,
                                           first_detected_at: Time.current, detected_at: Time.current)
      account.revenue_risk_signals.create!(category: 'risk', signal_type: 'deal_stalled', subject_type: 'RevenueDeal', subject_id: deal.id,
                                           first_detected_at: Time.current, detected_at: Time.current)

      result = builder.build

      labels = result[:risk_signals][:open].to_h { |s| [s['subject_type'], s['subject_label']] }
      expect(labels['RevenueLead']).to eq('Ana Pérez')
      expect(labels['RevenueDeal']).to eq('Ana Pérez - Depto 302')
    end

    it 'falls back to the phone when a lead has no name in raw_payload' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', raw_payload: { 'Phone' => '9981234567' })
      account.revenue_risk_signals.create!(category: 'risk', signal_type: 'lead_no_contact', subject_type: 'RevenueLead', subject_id: lead.id,
                                           first_detected_at: Time.current, detected_at: Time.current)

      result = builder.build

      expect(result[:risk_signals][:open].first['subject_label']).to eq('9981234567')
    end

    it "resolves subject_label for RevenueIdentityConflict from match_key, instead of a raw 'RevenueIdentityConflict #id'" do
      conflict = account.revenue_identity_conflicts.create!(conflict_type: 'multiple_candidates', match_key: '9981234567',
                                                            candidate_ids: [1, 2])
      account.revenue_risk_signals.create!(category: 'data_quality', signal_type: 'unresolved_identity_conflict',
                                           subject_type: 'RevenueIdentityConflict', subject_id: conflict.id,
                                           first_detected_at: Time.current, detected_at: Time.current)

      result = builder.build

      expect(result[:risk_signals][:open].first['subject_label']).to eq('9981234567 (2 candidatos)')
    end

    it 'summarizes journeys created within the range: won/lost/open counts and average time-to-X, ignoring nil milestones' do
      lead1 = account.revenue_leads.create!(zoho_lead_id: 'l1')
      lead2 = account.revenue_leads.create!(zoho_lead_id: 'l2')
      lead3 = account.revenue_leads.create!(zoho_lead_id: 'l3')
      account.revenue_lead_journeys.create!(revenue_lead: lead1, lead_created_at: 5.days.ago, won: true,
                                            time_to_first_response_seconds: 60)
      account.revenue_lead_journeys.create!(revenue_lead: lead2, lead_created_at: 5.days.ago, lost: true,
                                            time_to_first_response_seconds: 120)
      account.revenue_lead_journeys.create!(revenue_lead: lead3, lead_created_at: 5.days.ago) # sin ese hito -> no cuenta como 0

      result = builder.build

      expect(result[:journeys]).to eq({ total: 3, won: 1, lost: 1, open: 1, avg_time_to_first_response_seconds: 90,
                                        avg_time_to_qualification_seconds: nil, avg_time_to_appointment_seconds: nil,
                                        avg_time_to_close_seconds: nil })
    end

    it 'builds a daily funnel_trend series only for the requested metrics' do
      rollup('funnel', 'Fuego', 'lead_created', count: 2, date: 3.days.ago.to_date)
      rollup('funnel', 'OtroDesarrollo', 'lead_created', count: 1, date: 3.days.ago.to_date)
      rollup('funnel', 'Fuego', 'closed_won', count: 1, date: 2.days.ago.to_date)
      rollup('funnel', 'Fuego', 'reserved', count: 5, date: 2.days.ago.to_date) # no está en FUNNEL_TREND_METRICS

      result = builder.build

      expect(result[:funnel_trend][3.days.ago.to_date.to_s]).to eq({ 'lead_created' => 3 })
      expect(result[:funnel_trend][2.days.ago.to_date.to_s]).to eq({ 'closed_won' => 1 })
    end

    it 'defaults to the last 30 days when since/until are not given' do
      rollup('funnel', 'Fuego', 'lead_created', count: 1, date: 10.days.ago.to_date)
      rollup('funnel', 'Fuego', 'lead_created', count: 1, date: 40.days.ago.to_date)

      result = described_class.new(account: account, params: {}).build

      expect(result[:funnel]['Fuego']['lead_created']).to eq(1)
    end
  end

  describe 'funnel_totals' do
    it 'sums every FUNNEL_EVENT_TYPES stage across all desarrollos, anchored to the event date' do
      rollup('funnel', 'Fuego', 'lead_created', count: 10, date: 5.days.ago.to_date)
      rollup('funnel', 'OtroDesarrollo', 'lead_created', count: 4, date: 5.days.ago.to_date)

      result = builder.build

      expect(result[:funnel_totals]['lead_created'][:count]).to eq(14)
    end

    it 'compares against the same-length period immediately before the selected range' do
      rollup('funnel', 'Fuego', 'lead_created', count: 10, date: 5.days.ago.to_date) # dentro del rango (últimos 20 días)
      rollup('funnel', 'Fuego', 'lead_created', count: 8, date: 30.days.ago.to_date) # periodo anterior

      result = builder.build

      totals = result[:funnel_totals]['lead_created']
      expect(totals).to eq({ count: 10, previous_count: 8, delta_pct: 25.0, seguimiento_count: 0 })
    end

    it 'leaves delta_pct nil when there is no data for the previous period (avoids a division by zero)' do
      rollup('funnel', 'Fuego', 'lead_created', count: 10, date: 5.days.ago.to_date)

      result = builder.build

      expect(result[:funnel_totals]['lead_created']).to eq({ count: 10, previous_count: 0, delta_pct: nil, seguimiento_count: 0 })
    end

    it 'counts a stage event as "seguimiento" when its lead was created before the selected range' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', created_at_source: 40.days.ago)
      account.revenue_events.create!(event_type: 'lead_contacted', event_at: 5.days.ago, source_system: 'test', source_id: '1',
                                     zoho_lead_id: lead.zoho_lead_id)

      result = builder.build

      expect(result[:funnel_totals]['lead_contacted'][:seguimiento_count]).to eq(1)
    end

    it 'does not count a stage event as "seguimiento" when its lead was created within the selected range' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', created_at_source: 5.days.ago)
      account.revenue_events.create!(event_type: 'lead_contacted', event_at: 5.days.ago, source_system: 'test', source_id: '1',
                                     zoho_lead_id: lead.zoho_lead_id)

      result = builder.build

      expect(result[:funnel_totals]['lead_contacted'][:seguimiento_count]).to eq(0)
    end

    it 'resolves the lead via the deal when the event only carries zoho_deal_id' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', created_at_source: 40.days.ago)
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', revenue_lead_id: lead.id)
      account.revenue_events.create!(event_type: 'closed_won', event_at: 5.days.ago, source_system: 'test', source_id: '1',
                                     zoho_deal_id: 'deal-1')

      result = builder.build

      expect(result[:funnel_totals]['closed_won'][:seguimiento_count]).to eq(1)
    end

    it 'defaults to "not seguimiento" when the lead/deal cannot be resolved (identity not yet linked)' do
      account.revenue_events.create!(event_type: 'lead_contacted', event_at: 5.days.ago, source_system: 'test', source_id: '1',
                                     zoho_lead_id: 'unresolved-lead')

      result = builder.build

      expect(result[:funnel_totals]['lead_contacted'][:seguimiento_count]).to eq(0)
    end
  end

  describe 'funnel_conversions' do
    it 'computes the stage-to-stage rate following FUNNEL_SEQUENCE' do
      rollup('funnel', 'Fuego', 'lead_created', count: 100)
      rollup('funnel', 'Fuego', 'lead_contacted', count: 40)

      result = builder.build

      expect(result[:funnel_conversions]['lead_contacted']).to eq(0.4)
    end
  end

  describe 'insights' do
    it 'flags the CTA conversion comparison when both segments have volume' do
      rollup('call_conversion', 'cta_used:true', 'total', count: 10)
      rollup('call_conversion', 'cta_used:true', 'converted', count: 4)
      rollup('call_conversion', 'cta_used:false', 'total', count: 10)
      rollup('call_conversion', 'cta_used:false', 'converted', count: 2)

      result = builder.build

      insight = result[:insights].find { |i| i[:type] == 'cta_conversion' }
      expect(insight).to eq({ type: 'cta_conversion', direction: 'up', params: { used_rate: 40.0, not_used_rate: 20.0 } })
    end

    it 'does not include the CTA insight when one of the two segments has no volume yet' do
      rollup('call_conversion', 'cta_used:true', 'total', count: 10)
      rollup('call_conversion', 'cta_used:true', 'converted', count: 4)

      result = builder.build

      expect(result[:insights].find { |i| i[:type] == 'cta_conversion' }).to be_nil
    end

    it 'flags the best-converting intent_level segment when it has at least 3 calls' do
      rollup('call_conversion', 'intent_level:alta', 'total', count: 5)
      rollup('call_conversion', 'intent_level:alta', 'converted', count: 4)
      rollup('call_conversion', 'intent_level:baja', 'total', count: 5)
      rollup('call_conversion', 'intent_level:baja', 'converted', count: 1)

      result = builder.build

      insight = result[:insights].find { |i| i[:type] == 'intent_level_conversion' }
      expect(insight).to eq({ type: 'intent_level_conversion', direction: 'up', params: { level: 'alta', rate: 80.0 } })
    end

    it 'flags the worst-converting objection only when it is below the overall average and has enough volume' do
      rollup('objection_conversion', 'financiera', 'total', count: 10)
      rollup('objection_conversion', 'financiera', 'converted', count: 2)
      rollup('objection_conversion', 'producto', 'total', count: 10)
      rollup('objection_conversion', 'producto', 'converted', count: 6)

      result = builder.build

      insight = result[:insights].find { |i| i[:type] == 'worst_objection' }
      expect(insight[:params][:category]).to eq('financiera')
      expect(insight[:params][:rate]).to eq(20.0)
    end

    it 'does not flag an objection insight when there is only one objection to compare' do
      rollup('objection_conversion', 'financiera', 'total', count: 10)
      rollup('objection_conversion', 'financiera', 'converted', count: 2)

      result = builder.build

      expect(result[:insights].find { |i| i[:type] == 'worst_objection' }).to be_nil
    end

    it 'compares appointment-reached rate between fast (<=15min) and slow first-response journeys' do
      leads = Array.new(6) { |i| account.revenue_leads.create!(zoho_lead_id: "l#{i}") }
      leads.first(3).each do |lead|
        account.revenue_lead_journeys.create!(revenue_lead: lead, lead_created_at: 5.days.ago, time_to_first_response_seconds: 60,
                                              appointment_at: 1.day.ago)
      end
      leads.last(3).each do |lead|
        account.revenue_lead_journeys.create!(revenue_lead: lead, lead_created_at: 5.days.ago, time_to_first_response_seconds: 3600)
      end

      result = builder.build

      insight = result[:insights].find { |i| i[:type] == 'response_time_conversion' }
      expect(insight).to eq({ type: 'response_time_conversion', direction: 'up', params: { fast_rate: 100.0, slow_rate: 0.0 } })
    end

    it 'reports the count of open lead_no_contact risk signals' do
      account.revenue_risk_signals.create!(category: 'risk', signal_type: 'lead_no_contact', subject_type: 'RevenueLead', subject_id: 1,
                                           severity: 'high', first_detected_at: Time.current, detected_at: Time.current)
      account.revenue_risk_signals.create!(category: 'risk', signal_type: 'lead_no_contact', subject_type: 'RevenueLead', subject_id: 2,
                                           severity: 'high', first_detected_at: Time.current, detected_at: Time.current)

      result = builder.build

      expect(result[:insights].find { |i| i[:type] == 'leads_no_contact' }).to eq({ type: 'leads_no_contact', direction: 'warning',
                                                                                    params: { count: 2 } })
    end

    it 'does not report the risk insight when there are no open lead_no_contact signals' do
      result = builder.build

      expect(result[:insights].find { |i| i[:type] == 'leads_no_contact' }).to be_nil
    end
  end
end
