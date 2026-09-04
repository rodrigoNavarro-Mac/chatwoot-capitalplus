require 'rails_helper'

describe V2::Reports::RevenueIntelligenceBuilder do
  let(:account) { create(:account) }
  let(:params) { { since: 20.days.ago.to_i.to_s, until: Time.current.to_i.to_s } }
  let(:builder) { described_class.new(account: account, params: params) }

  # rubocop:disable Metrics/ParameterLists
  def rollup(dimension_type, dimension_id, metric, count: 1, sum_value: 0, date: 5.days.ago.to_date)
    account.revenue_rollups.create!(date: date, dimension_type: dimension_type, dimension_id: dimension_id, metric: metric, count: count,
                                    sum_value: sum_value)
  end
  # rubocop:enable Metrics/ParameterLists

  describe '#build' do
    it 'sums funnel rollups by dimension_id and metric within the date range' do
      rollup('funnel', 'Fuego', 'lead_created', count: 3)
      rollup('funnel', 'Fuego', 'lead_created', count: 2, date: 6.days.ago.to_date)
      rollup('funnel', 'Fuego', 'closed_won', count: 1)
      rollup('funnel', 'Fuego', 'lead_created', count: 100, date: 60.days.ago.to_date) # fuera del rango

      result = builder.build

      expect(result[:funnel]).to eq({ 'Fuego' => { 'lead_created' => 5, 'closed_won' => 1 } })
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
      expect(campaign[:metrics]).to eq({ 'lead_created' => 10 })
      adset = campaign[:adsets].first
      expect(adset).to include(id: 'adset-1', name: 'Adset Uno', metrics: { 'lead_created' => 6 })
      expect(adset[:adverts].first).to eq({ id: 'ad-1', name: 'Anuncio Uno', metrics: { 'lead_created' => 4 } })
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
      expect(totals).to eq({ count: 10, previous_count: 8, delta_pct: 25.0 })
    end

    it 'leaves delta_pct nil when there is no data for the previous period (avoids a division by zero)' do
      rollup('funnel', 'Fuego', 'lead_created', count: 10, date: 5.days.ago.to_date)

      result = builder.build

      expect(result[:funnel_totals]['lead_created']).to eq({ count: 10, previous_count: 0, delta_pct: nil })
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
