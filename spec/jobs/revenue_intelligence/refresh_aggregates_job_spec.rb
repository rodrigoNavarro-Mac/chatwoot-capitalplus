require 'rails_helper'

describe RevenueIntelligence::RefreshAggregatesJob do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let!(:revenue_contact) do
    account.revenue_contacts.create!(chatwoot_contact_id: contact.id, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  before do
    account.enable_features!('crm_integration')
    create(:integrations_hook, :zoho_crm, account: account, status: 'enabled')
  end

  def add_event(event_type, event_at, **attrs)
    account.revenue_events.create!(event_type: event_type, event_at: event_at, source_system: 'test', source_id: SecureRandom.hex(4), **attrs)
  end

  describe 'funnel dimension' do
    it 'buckets by desarrollo inherited from the lead, and uses the event_type as the metric name' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', desarrollo: 'Fuego')
      add_event('lead_created', Time.current, zoho_lead_id: lead.zoho_lead_id, revenue_contact_id: revenue_contact.id)

      described_class.new.perform

      rollup = account.revenue_rollups.find_by(dimension_type: 'funnel', dimension_id: 'Fuego', metric: 'lead_created')
      expect(rollup.count).to eq(1)
    end

    it 'prefers the deal desarrollo over the lead desarrollo when the event carries a zoho_deal_id' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', desarrollo: 'Fuego')
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', revenue_lead_id: lead.id, desarrollo: 'OtroDesarrollo')
      add_event('deal_created', Time.current, zoho_lead_id: lead.zoho_lead_id, zoho_deal_id: 'deal-1', revenue_contact_id: revenue_contact.id)

      described_class.new.perform

      expect(account.revenue_rollups.find_by(dimension_type: 'funnel', dimension_id: 'OtroDesarrollo', metric: 'deal_created')).to be_present
    end

    it 'falls back to "_all" when no desarrollo can be resolved' do
      add_event('lead_created', Time.current, revenue_contact_id: revenue_contact.id)

      described_class.new.perform

      expect(account.revenue_rollups.find_by(dimension_type: 'funnel', dimension_id: '_all', metric: 'lead_created')).to be_present
    end

    it 'accumulates count across separate runs instead of overwriting it' do
      add_event('lead_created', Time.current, revenue_contact_id: revenue_contact.id)
      described_class.new.perform
      # simula una segunda corrida en una ventana posterior con OTRO evento del mismo día
      add_event('lead_created', Time.current, revenue_contact_id: revenue_contact.id)

      described_class.new.perform

      rollup = account.revenue_rollups.find_by(dimension_type: 'funnel', dimension_id: '_all', metric: 'lead_created')
      expect(rollup.count).to eq(2)
    end

    it 'does not aggregate a non-funnel event_type (e.g. whatsapp_incoming)' do
      add_event('whatsapp_incoming', Time.current, revenue_contact_id: revenue_contact.id)

      described_class.new.perform

      expect(account.revenue_rollups.where(dimension_type: 'funnel')).to be_empty
    end

    it 'aggregates lead_contacted and lead_qualified (etapas intermedias del embudo)' do
      add_event('lead_contacted', Time.current, revenue_contact_id: revenue_contact.id)
      add_event('lead_qualified', Time.current, revenue_contact_id: revenue_contact.id)

      described_class.new.perform

      expect(account.revenue_rollups.find_by(dimension_type: 'funnel', dimension_id: '_all', metric: 'lead_contacted')).to be_present
      expect(account.revenue_rollups.find_by(dimension_type: 'funnel', dimension_id: '_all', metric: 'lead_qualified')).to be_present
    end
  end

  describe 'desarrollo column (selector global de Revenue Intelligence)' do
    it 'attributes agent activity to the desarrollo of the deal carried on the event, over the lead' do
      agent = create(:user, account: account)
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', desarrollo: 'Fuego')
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', revenue_lead_id: lead.id, desarrollo: 'OtroDesarrollo')
      add_event('call_answered', Time.current, agent_id: agent.id, zoho_lead_id: lead.zoho_lead_id, zoho_deal_id: 'deal-1',
                                               revenue_contact_id: revenue_contact.id)

      described_class.new.perform

      rollup = account.revenue_rollups.find_by(dimension_type: 'agent', dimension_id: agent.id.to_s, metric: 'call_answered')
      expect(rollup.desarrollo).to eq('OtroDesarrollo')
    end

    it 'attributes agent_call_quality rows (score_sum/cta_used_count) to the desarrollo of the linked deal' do
      agent = create(:user, account: account)
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', desarrollo: 'Fuego')
      started_at = 2.days.ago
      feature_call = create(:call, account: account, conversation: create(:conversation, account: account, contact: contact),
                                   contact: contact, status: 'completed', started_at: started_at)
      analysis = create(:call_analysis, call: feature_call, account: account, status: 'completed')
      account.revenue_call_features.create!(call_id: feature_call.id, call_analysis_id: analysis.id, revenue_contact_id: revenue_contact.id,
                                            agent_id: agent.id, zoho_deal_id: 'deal-1', started_at: started_at, cta_used: true, score_total: 80.0)

      described_class.new.perform

      scope = account.revenue_rollups.where(dimension_type: 'agent', dimension_id: agent.id.to_s)
      expect(scope.find_by(metric: 'calls_scored').desarrollo).to eq('Fuego')
      expect(scope.find_by(metric: 'score_sum').desarrollo).to eq('Fuego')
      expect(scope.find_by(metric: 'cta_used_count').desarrollo).to eq('Fuego')
    end

    it 'attributes campaign/adset/advert rows to the desarrollo column already present on the lead' do
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', campaign_id: 'camp-1', adset_id: 'adset-1', desarrollo: 'Fuego',
                                    created_at_source: Time.current)

      described_class.new.perform

      expect(account.revenue_rollups.find_by(dimension_type: 'campaign', dimension_id: 'camp-1').desarrollo).to eq('Fuego')
      expect(account.revenue_rollups.find_by(dimension_type: 'adset').desarrollo).to eq('Fuego')
    end

    it 'attributes pipeline_stage rows to the desarrollo of the deal referenced by zoho_deal_id' do
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', desarrollo: 'Fuego')
      account.revenue_stage_events.create!(zoho_deal_id: 'deal-1', stage: 'Apartado', entered_at: Time.current)

      described_class.new.perform

      rollup = account.revenue_rollups.find_by(dimension_type: 'pipeline_stage', dimension_id: 'Apartado', metric: 'entered')
      expect(rollup.desarrollo).to eq('Fuego')
    end

    it 'attributes call_conversion rows to the desarrollo of the call feature\'s linked deal' do
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', desarrollo: 'Fuego')
      started_at = 2.days.ago
      feature_call = create(:call, account: account, conversation: create(:conversation, account: account, contact: contact),
                                   contact: contact, status: 'completed', started_at: started_at)
      analysis = create(:call_analysis, call: feature_call, account: account, status: 'completed')
      account.revenue_call_features.create!(call_id: feature_call.id, call_analysis_id: analysis.id, revenue_contact_id: revenue_contact.id,
                                            zoho_deal_id: 'deal-1', started_at: started_at, cta_used: true)

      described_class.new.perform

      rollup = account.revenue_rollups.find_by(dimension_type: 'call_conversion', dimension_id: 'cta_used:true', metric: 'total')
      expect(rollup.desarrollo).to eq('Fuego')
    end

    it 'attributes objection_conversion rows to the desarrollo of the analyzed call\'s linked deal' do
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', desarrollo: 'Fuego')
      call = create(:call, account: account, conversation: create(:conversation, account: account, contact: contact), contact: contact,
                           status: 'completed', started_at: 2.days.ago)
      analysis = create(:call_analysis, call: call, account: account, status: 'completed', analyzed_at: 2.days.ago,
                                        objections: [{ 'category' => 'financiera' }])
      account.revenue_call_features.create!(call_id: call.id, call_analysis_id: analysis.id, revenue_contact_id: revenue_contact.id,
                                            zoho_deal_id: 'deal-1', started_at: 2.days.ago)

      described_class.new.perform

      rollup = account.revenue_rollups.find_by(dimension_type: 'objection_conversion', dimension_id: 'financiera', metric: 'total')
      expect(rollup.desarrollo).to eq('Fuego')
    end
  end

  describe 'agent dimension' do
    it 'buckets call activity by the Chatwoot agent_id carried on the event' do
      agent = create(:user, account: account)
      add_event('call_answered', Time.current, agent_id: agent.id, revenue_contact_id: revenue_contact.id)

      described_class.new.perform

      rollup = account.revenue_rollups.find_by(dimension_type: 'agent', dimension_id: agent.id.to_s, metric: 'call_answered')
      expect(rollup.count).to eq(1)
    end

    it 'skips agent events without an agent_id' do
      add_event('call_started', Time.current, revenue_contact_id: revenue_contact.id)

      described_class.new.perform

      expect(account.revenue_rollups.where(dimension_type: 'agent')).to be_empty
    end

    it 'aggregates score_sum/cta_used_count from revenue_call_features, keyed by agent_id' do
      agent = create(:user, account: account)
      started_at = 2.days.ago
      feature_call = create(:call, account: account, conversation: create(:conversation, account: account, contact: contact), contact: contact,
                                   status: 'completed', started_at: started_at)
      analysis = create(:call_analysis, call: feature_call, account: account, status: 'completed')
      account.revenue_call_features.create!(call_id: feature_call.id, call_analysis_id: analysis.id, revenue_contact_id: revenue_contact.id,
                                            agent_id: agent.id, started_at: started_at, cta_used: true, score_total: 80.0)

      described_class.new.perform

      scope = account.revenue_rollups.where(dimension_type: 'agent', dimension_id: agent.id.to_s)
      expect(scope.find_by(metric: 'calls_scored').count).to eq(1)
      expect(scope.find_by(metric: 'score_sum').sum_value).to eq(80.0)
      expect(scope.find_by(metric: 'cta_used_count').count).to eq(1)
    end

    it 'does not emit a cta_used_count row when the call did not use a CTA' do
      agent = create(:user, account: account)
      started_at = 2.days.ago
      feature_call = create(:call, account: account, conversation: create(:conversation, account: account, contact: contact), contact: contact,
                                   status: 'completed', started_at: started_at)
      analysis = create(:call_analysis, call: feature_call, account: account, status: 'completed')
      account.revenue_call_features.create!(call_id: feature_call.id, call_analysis_id: analysis.id, revenue_contact_id: revenue_contact.id,
                                            agent_id: agent.id, started_at: started_at, cta_used: false, score_total: nil)

      described_class.new.perform

      scope = account.revenue_rollups.where(dimension_type: 'agent', dimension_id: agent.id.to_s)
      expect(scope.find_by(metric: 'calls_scored').count).to eq(1)
      expect(scope.find_by(metric: 'cta_used_count')).to be_nil
      expect(scope.find_by(metric: 'score_sum')).to be_nil
    end
  end

  describe 'campaign dimension' do
    it 'counts lead_created by campaign_id directly from revenue_leads' do
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', campaign_id: 'camp-1', created_at_source: Time.current)

      described_class.new.perform

      rollup = account.revenue_rollups.find_by(dimension_type: 'campaign', dimension_id: 'camp-1', metric: 'lead_created')
      expect(rollup.count).to eq(1)
    end

    it 'attributes closed_won to the campaign_id of the deal\'s originating lead' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', campaign_id: 'camp-1')
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', revenue_lead_id: lead.id, won: true, stage: 'Cerrado ganado')

      described_class.new.perform

      rollup = account.revenue_rollups.find_by(dimension_type: 'campaign', dimension_id: 'camp-1', metric: 'closed_won')
      expect(rollup.count).to eq(1)
    end

    it 'also emits adset/advert rows with the name embedded in a composite dimension_id when present' do
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', campaign_id: 'camp-1', adset_id: 'adset-1', adset_name: 'Adset Uno',
                                    advert_id: 'ad-1', advert_name: 'Anuncio Uno', created_at_source: Time.current)

      described_class.new.perform

      expect(account.revenue_rollups.find_by(dimension_type: 'adset', dimension_id: 'camp-1::adset-1::Adset Uno',
                                             metric: 'lead_created')).to be_present
      expect(account.revenue_rollups.find_by(dimension_type: 'advert', dimension_id: 'camp-1::adset-1::ad-1::Anuncio Uno',
                                             metric: 'lead_created')).to be_present
    end

    it 'falls back to the raw id as the display name when adset_name/advert_name are blank' do
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', campaign_id: 'camp-1', adset_id: 'adset-1', adset_name: nil,
                                    created_at_source: Time.current)

      described_class.new.perform

      expect(account.revenue_rollups.find_by(dimension_type: 'adset', dimension_id: 'camp-1::adset-1::adset-1',
                                             metric: 'lead_created')).to be_present
    end

    it 'does not emit an adset row when the lead has no adset_id, even with a campaign_id' do
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', campaign_id: 'camp-1', created_at_source: Time.current)

      described_class.new.perform

      expect(account.revenue_rollups.where(dimension_type: 'adset')).to be_empty
      expect(account.revenue_rollups.where(dimension_type: 'advert')).to be_empty
    end

    it 'does not emit an advert row when the lead has an adset_id but no advert_id' do
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', campaign_id: 'camp-1', adset_id: 'adset-1', created_at_source: Time.current)

      described_class.new.perform

      expect(account.revenue_rollups.where(dimension_type: 'adset')).not_to be_empty
      expect(account.revenue_rollups.where(dimension_type: 'advert')).to be_empty
    end
  end

  describe 'pipeline_stage dimension' do
    it 'counts an "entered" row for every new stage_event, bucketed by entered_at' do
      account.revenue_stage_events.create!(zoho_deal_id: 'deal-1', stage: 'Apartado', entered_at: Time.current)

      described_class.new.perform

      rollup = account.revenue_rollups.find_by(dimension_type: 'pipeline_stage', dimension_id: 'Apartado', metric: 'entered')
      expect(rollup.count).to eq(1)
    end

    it 'sums duration_seconds only for stage_events that already closed' do
      account.revenue_stage_events.create!(zoho_deal_id: 'deal-1', stage: 'Apartado', entered_at: Time.current, exited_at: Time.current,
                                           duration_seconds: 432_000)
      account.revenue_stage_events.create!(zoho_deal_id: 'deal-2', stage: 'Apartado', entered_at: Time.current) # abierta, sin exited_at

      described_class.new.perform

      rollup = account.revenue_rollups.find_by(dimension_type: 'pipeline_stage', dimension_id: 'Apartado', metric: 'duration_seconds')
      expect(rollup.sum_value.to_i).to eq(432_000)
      expect(account.revenue_rollups.find_by(dimension_type: 'pipeline_stage', dimension_id: 'Apartado', metric: 'entered').count).to eq(2)
    end
  end

  describe 'call_conversion dimension' do
    it 'counts a call as "converted" only when an appointment_created event happens after the call started' do
      started_at = 2.days.ago
      feature_call = create(:call, account: account, conversation: create(:conversation, account: account, contact: contact), contact: contact,
                                   status: 'completed', started_at: started_at)
      analysis = create(:call_analysis, call: feature_call, account: account, status: 'completed', intent_level: 'alta',
                                        scorecard: { 'total_score' => 85.0 })
      account.revenue_call_features.create!(call_id: feature_call.id, call_analysis_id: analysis.id, revenue_contact_id: revenue_contact.id,
                                            started_at: started_at, cta_used: true, intent_level: 'alta', score_total: 85.0)
      add_event('appointment_created', 1.day.ago, revenue_contact_id: revenue_contact.id)

      described_class.new.perform

      cta_rollup = account.revenue_rollups.where(dimension_type: 'call_conversion', dimension_id: 'cta_used:true')
      expect(cta_rollup.find_by(metric: 'total').count).to eq(1)
      expect(cta_rollup.find_by(metric: 'converted').count).to eq(1)
      expect(account.revenue_rollups.find_by(dimension_type: 'call_conversion', dimension_id: 'intent_level:alta',
                                             metric: 'converted')).to be_present
      expect(account.revenue_rollups.find_by(dimension_type: 'call_conversion', dimension_id: 'score_band:70-100',
                                             metric: 'converted')).to be_present
    end

    it 'does not mark a call as converted when the only appointment happened before it started' do
      started_at = Time.current
      feature_call = create(:call, account: account, conversation: create(:conversation, account: account, contact: contact), contact: contact,
                                   status: 'completed', started_at: started_at)
      analysis = create(:call_analysis, call: feature_call, account: account, status: 'completed')
      account.revenue_call_features.create!(call_id: feature_call.id, call_analysis_id: analysis.id, revenue_contact_id: revenue_contact.id,
                                            started_at: started_at, cta_used: false)
      add_event('appointment_created', 1.day.ago, revenue_contact_id: revenue_contact.id) # antes de la llamada

      described_class.new.perform

      cta_rollup = account.revenue_rollups.where(dimension_type: 'call_conversion', dimension_id: 'cta_used:false')
      expect(cta_rollup.find_by(metric: 'total').count).to eq(1)
      expect(cta_rollup.find_by(metric: 'converted')).to be_nil
    end
  end

  describe 'objection_conversion dimension' do
    it 'counts objections by category from call_analyses.objections, cross-referenced with appointment conversion' do
      call = create(:call, account: account, conversation: create(:conversation, account: account, contact: contact), contact: contact,
                           status: 'completed', started_at: 2.days.ago)
      analysis = create(:call_analysis, call: call, account: account, status: 'completed', analyzed_at: 2.days.ago,
                                        objections: [{ 'category' => 'financiera' }, { 'category' => 'producto' }])
      account.revenue_call_features.create!(call_id: call.id, call_analysis_id: analysis.id, revenue_contact_id: revenue_contact.id,
                                            started_at: 2.days.ago)
      add_event('appointment_created', 1.day.ago, revenue_contact_id: revenue_contact.id)

      described_class.new.perform

      financiera = account.revenue_rollups.where(dimension_type: 'objection_conversion', dimension_id: 'financiera')
      expect(financiera.find_by(metric: 'total').count).to eq(1)
      expect(financiera.find_by(metric: 'converted').count).to eq(1)
      expect(account.revenue_rollups.find_by(dimension_type: 'objection_conversion', dimension_id: 'producto', metric: 'total')).to be_present
    end
  end

  describe '#perform' do
    it 'is idempotent within the same run scope — re-running an empty window adds nothing new' do
      add_event('lead_created', Time.current, revenue_contact_id: revenue_contact.id)
      described_class.new.perform
      first_count = account.revenue_rollups.find_by(dimension_type: 'funnel', dimension_id: '_all', metric: 'lead_created').count

      described_class.new.perform # sin eventos nuevos en la ventana

      expect(account.revenue_rollups.find_by(dimension_type: 'funnel', dimension_id: '_all', metric: 'lead_created').count).to eq(first_count)
    end

    it 'only aggregates the given account when an account_id is passed' do
      other_account = create(:account)
      other_account.enable_features!('crm_integration')
      create(:integrations_hook, :zoho_crm, account: other_account, status: 'enabled')
      other_contact = create(:contact, account: other_account)
      other_revenue_contact = other_account.revenue_contacts.create!(chatwoot_contact_id: other_contact.id, first_seen_at: Time.current,
                                                                     last_seen_at: Time.current)
      other_account.revenue_events.create!(event_type: 'lead_created', event_at: Time.current, source_system: 'test', source_id: '1',
                                           revenue_contact_id: other_revenue_contact.id)
      add_event('lead_created', Time.current, revenue_contact_id: revenue_contact.id)

      described_class.new.perform(account.id)

      expect(account.revenue_rollups.where(dimension_type: 'funnel')).to exist
      expect(other_account.revenue_rollups.where(dimension_type: 'funnel')).to be_empty
    end
  end
end
