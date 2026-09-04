# Agrega revenue_events (+ Call/CallAnalysis directamente para scores e intent, para no perder
# precisión ni tener que parsear metadata jsonb) en revenue_lead_journeys — una fila "lista para
# leer" por RevenueLead. Corre después de RevenueIntelligence::BuildEventsJob en el cron.
#
# Qué leads se reconstruyen en cada corrida: los que pertenecen a un revenue_contact que tuvo AL
# MENOS un revenue_events nuevo (por created_at, no event_at — así un backfill de eventos viejos
# también dispara la reconstrucción) desde el último cursor "journeys". Una vez elegido un lead,
# se reconstruye completo desde TODO su historial de eventos, no solo los nuevos — más simple y
# siempre correcto que ir parcheando campos incrementalmente.
class RevenueIntelligence::BuildJourneysJob < ApplicationJob
  queue_as :scheduled_jobs

  MILESTONE_EVENT_TYPES = {
    lead_created_at: 'lead_created',
    first_response_at: 'first_response',
    first_call_at: 'call_started',
    first_answered_call_at: 'call_answered',
    qualified_at: 'lead_qualified',
    deal_created_at: 'deal_created',
    appointment_at: 'appointment_created',
    visit_at: 'visit_effective',
    reserved_at: 'reserved'
  }.freeze

  INTENT_RANK = { 'baja' => 1, 'media' => 2, 'alta' => 3 }.freeze

  def perform(account_id = nil)
    hooks = Integrations::Hook.enabled.where(app_id: 'zoho_crm')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      build_for_account(hook.account)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::BuildJourneysJob] account=#{hook.account_id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: hook.account).capture_exception
    end
  end

  private

  def build_for_account(account)
    cursor_service = RevenueIntelligence::SyncCursorService.new(account, 'journeys')
    since = cursor_service.since
    until_at = Time.current
    contact_ids = touched_contact_ids(account, since, until_at)

    account.revenue_leads.where(revenue_contact_id: contact_ids).find_each do |lead|
      rebuild_journey(account, lead)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::BuildJourneysJob] lead=#{lead.id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: account).capture_exception
    end

    cursor_service.advance!(until_at)
  rescue StandardError => e
    cursor_service&.record_error!(e.message)
    raise
  end

  def touched_contact_ids(account, since, until_at)
    scope = account.revenue_events.where.not(revenue_contact_id: nil)
    scope = since ? scope.where(created_at: since...until_at) : scope.where(created_at: ..until_at)
    scope.distinct.pluck(:revenue_contact_id)
  end

  def rebuild_journey(account, lead)
    journey = account.revenue_lead_journeys.find_or_initialize_by(revenue_lead_id: lead.id)
    journey.assign_attributes(journey_attrs(account, lead))
    journey.save!
  end

  def journey_attrs(account, lead)
    rows_by_type = account.revenue_events.where(revenue_contact_id: lead.revenue_contact_id).pluck(:event_type, :event_at)
                          .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
    milestones = build_milestones(rows_by_type, lead)
    deal = lead.revenue_deals.order(created_at: :desc).first

    identity_attrs(lead, deal)
      .merge(milestones)
      .merge(outcome_attrs(deal, milestones))
      .merge(time_to_attrs(milestones))
      .merge(activity_attrs(rows_by_type, account, lead))
      .merge(call_intelligence_attrs(account, lead))
      .merge(built_at: Time.current)
  end

  def identity_attrs(lead, deal)
    { revenue_contact_id: lead.revenue_contact_id, revenue_deal_id: deal&.id }
  end

  def build_milestones(rows_by_type, lead)
    milestones = MILESTONE_EVENT_TYPES.transform_values { |event_type| rows_by_type[event_type]&.min }
    # Respaldo: si por lo que sea todavía no existe el evento lead_created (no debería pasar en
    # operación normal), usa directamente el dato ya mapeado en Fase 1 en vez de dejarlo en null.
    milestones[:lead_created_at] ||= lead.created_at_source
    milestones[:closed_at] = (Array(rows_by_type['closed_won']) + Array(rows_by_type['closed_lost'])).min
    milestones
  end

  def outcome_attrs(deal, _milestones)
    { final_stage: deal&.stage, won: deal&.won || false, lost: deal&.lost || false }
  end

  def time_to_attrs(milestones)
    created_at = milestones[:lead_created_at]
    {
      time_to_first_response_seconds: seconds_between(created_at, milestones[:first_response_at]),
      time_to_first_call_seconds: seconds_between(created_at, milestones[:first_call_at]),
      time_to_qualification_seconds: seconds_between(created_at, milestones[:qualified_at]),
      time_to_appointment_seconds: seconds_between(created_at, milestones[:appointment_at]),
      time_to_visit_seconds: seconds_between(created_at, milestones[:visit_at]),
      time_to_close_seconds: seconds_between(created_at, milestones[:closed_at])
    }
  end

  def seconds_between(from, to)
    return nil if from.blank? || to.blank?

    (to - from).round
  end

  ACTIVITY_EVENT_TYPES = {
    incoming_messages: 'whatsapp_incoming', outgoing_messages: 'whatsapp_outgoing', calls_attempted: 'call_started',
    calls_answered: 'call_answered', calls_missed: 'call_missed'
  }.freeze

  def activity_attrs(rows_by_type, account, lead)
    counts = ACTIVITY_EVENT_TYPES.transform_values { |event_type| rows_by_type[event_type]&.size || 0 }
    counts.merge(call_activity_from_source(account, lead))
  end

  # total_call_seconds/unique_agents no están en los eventos (no cargan duración/agente en su
  # metadata) — se leen directo de `calls`, igual que los scores de call_analyses más abajo.
  def call_activity_from_source(account, lead)
    calls = calls_for(account, lead)
    return { total_call_seconds: 0, unique_agents: 0 } unless calls

    {
      total_call_seconds: calls.sum(:duration_seconds) || 0,
      unique_agents: calls.where.not(accepted_by_agent_id: nil).distinct.count(:accepted_by_agent_id)
    }
  end

  def calls_for(account, lead)
    chatwoot_contact_id = lead.revenue_contact&.chatwoot_contact_id
    return nil if chatwoot_contact_id.blank?

    account.calls.where(contact_id: chatwoot_contact_id)
  end

  # Trae score/intent/objeciones/riesgos DIRECTO de call_analyses (no vía metadata de eventos) —
  # evita perder precisión decimal y no depende de qué se haya volcado a revenue_events.
  def call_intelligence_attrs(account, lead)
    calls = calls_for(account, lead)
    return empty_call_intelligence_attrs unless calls

    analyses = CallAnalysis.where(call_id: calls.select(:id), status: 'completed').order(:analyzed_at)
    return empty_call_intelligence_attrs if analyses.none?

    score_attrs(analyses).merge(intent_attrs(analyses)).merge(signal_count_attrs(analyses))
  end

  def score_attrs(analyses)
    scores = analyses.filter_map { |analysis| analysis.total_score&.to_f }
    { avg_call_score: scores.any? ? (scores.sum / scores.size).round(2) : nil, max_call_score: scores.max,
      last_call_score: analyses.last.total_score }
  end

  def intent_attrs(analyses)
    intents = analyses.filter_map(&:intent_level)
    { latest_intent: intents.last, max_intent: intents.max_by { |intent| INTENT_RANK[intent] || 0 } }
  end

  def signal_count_attrs(analyses)
    {
      cta_count: analyses.count { |analysis| analysis.metrics.is_a?(Hash) && analysis.metrics['cta_used'] == true },
      objections_count: analyses.sum { |analysis| Array(analysis.objections).size },
      risks_count: analyses.sum { |analysis| Array(analysis.risks).size }
    }
  end

  def empty_call_intelligence_attrs
    {
      latest_intent: nil, max_intent: nil, avg_call_score: nil, max_call_score: nil, last_call_score: nil,
      cta_count: 0, objections_count: 0, risks_count: 0
    }
  end
end
