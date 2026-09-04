# Puebla revenue_events a partir de fuentes crudas de solo lectura (messages/calls/call_analyses/
# conversations) y de las tablas revenue_* ya sincronizadas en Fase 1. Ver el plan de Fase 2
# ("Clasificación de eventos") para la tabla completa de qué produce cada event_type.
#
# Un solo cursor "events" (RevenueIntelligence::SyncCursorService) gobierna la ventana [since,
# until_at) para TODAS las fuentes — más simple que un cursor por fuente, aceptable porque todas
# se reconstruyen en la misma corrida. Riesgo aceptado y documentado: un mensaje/llamada de un
# contacto cuya identidad TODAVÍA no se resolvió en Zoho se salta (no se puede asociar a un
# revenue_contact) y, como el cursor avanza igual, no se reintenta después — mitigado por el
# orden del cron (ResolveIdentityJob corre a las :25, este job a las :30, misma hora) pero no
# 100% garantizado. Los eventos de lead/deal/stage/cita SÍ tienen su revenue_contact_id ya
# resuelto por definición (son producidos por tablas que Fase 1 ya vinculó).
class RevenueIntelligence::BuildEventsJob < ApplicationJob
  queue_as :scheduled_jobs

  TERMINAL_CALL_STATUSES = %w[completed no_answer failed rejected].freeze

  def perform(account_id = nil)
    hooks = Integrations::Hook.enabled.where(app_id: 'zoho_crm')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      build_for_account(hook.account)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::BuildEventsJob] account=#{hook.account_id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: hook.account).capture_exception
    end
  end

  private

  def build_for_account(account)
    cursor_service = RevenueIntelligence::SyncCursorService.new(account, 'events')
    since = cursor_service.since
    until_at = Time.current
    contacts = revenue_contact_lookup(account)

    build_message_events(account, since, until_at, contacts)
    build_first_response_events(account, since, until_at, contacts)
    build_call_events(account, since, until_at, contacts)
    build_call_analysis_events(account, since, until_at, contacts)
    build_lead_events(account, since, until_at)
    build_deal_events(account, since, until_at)
    build_stage_events(account, since, until_at)
    build_appointment_events(account, since, until_at)

    cursor_service.advance!(until_at)
  rescue StandardError => e
    cursor_service&.record_error!(e.message)
    raise
  end

  # chatwoot_contact_id -> revenue_contact_id, para no golpear la BD por cada mensaje/llamada.
  def revenue_contact_lookup(account)
    account.revenue_contacts.where.not(chatwoot_contact_id: nil).pluck(:chatwoot_contact_id, :id).to_h
  end

  # nil (since blank, primera corrida) -> rango sin límite inferior, para no saltarse todo el
  # histórico ya sincronizado por Fase 1 la primera vez que corre este job.
  def window(column, since, until_at)
    since ? { column => since...until_at } : { column => ..until_at }
  end

  def each_safely(account, scope, label)
    scope.find_each do |record|
      yield record
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::BuildEventsJob] #{label}=#{record.id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: account).capture_exception
    end
  end

  def build_message_events(account, since, until_at, contacts)
    whatsapp_inbox_ids = account.inboxes.where(channel_type: 'Channel::Whatsapp').ids
    return if whatsapp_inbox_ids.empty?

    messages = account.messages.where(inbox_id: whatsapp_inbox_ids, message_type: %i[incoming outgoing])
                      .where(window(:created_at, since, until_at))
    # reorder(nil): Message trae un default order propio — combinado con SELECT DISTINCT, Postgres
    # exige que las columnas del ORDER BY estén en el SELECT, y conversation_id solo no la cumple.
    conversation_contact = account.conversations.where(id: messages.reorder(nil).distinct.pluck(:conversation_id))
                                  .pluck(:id, :contact_id).to_h

    each_safely(account, messages, 'message') do |message|
      revenue_contact_id = contacts[conversation_contact[message.conversation_id]]
      event_type = message.incoming? ? 'whatsapp_incoming' : 'whatsapp_outgoing'
      upsert_event(account, event_type: event_type, event_at: message.created_at, source_system: 'chatwoot_message',
                            source_id: message.id.to_s, revenue_contact_id: revenue_contact_id, conversation_id: message.conversation_id)
    end
  end

  def build_first_response_events(account, since, until_at, contacts)
    conversations = account.conversations.where.not(first_reply_created_at: nil).where(window(:first_reply_created_at, since, until_at))

    each_safely(account, conversations, 'conversation') do |conversation|
      revenue_contact_id = contacts[conversation.contact_id]
      upsert_event(account, event_type: 'first_response', event_at: conversation.first_reply_created_at, source_system: 'conversation',
                            source_id: conversation.id.to_s, revenue_contact_id: revenue_contact_id, conversation_id: conversation.id)
    end
  end

  def build_call_events(account, since, until_at, contacts)
    calls = account.calls.where(window(:started_at, since, until_at))

    each_safely(account, calls, 'call') do |call|
      revenue_contact_id = contacts[call.contact_id]
      upsert_call_started(account, call, revenue_contact_id)
      upsert_call_resolution(account, call, revenue_contact_id) if TERMINAL_CALL_STATUSES.include?(call.status)
    end
  end

  def upsert_call_started(account, call, revenue_contact_id)
    upsert_event(account, event_type: 'call_started', event_at: call.started_at, source_system: 'chatwoot_call',
                          source_id: call.id.to_s, revenue_contact_id: revenue_contact_id, conversation_id: call.conversation_id,
                          call_id: call.id, agent_id: call.accepted_by_agent_id)
  end

  def upsert_call_resolution(account, call, revenue_contact_id)
    event_type = call.status == 'completed' ? 'call_answered' : 'call_missed'
    resolved_at = call.started_at + (call.duration_seconds || 0).seconds
    upsert_event(account, event_type: event_type, event_at: resolved_at, source_system: 'chatwoot_call',
                          source_id: call.id.to_s, revenue_contact_id: revenue_contact_id, conversation_id: call.conversation_id,
                          call_id: call.id, agent_id: call.accepted_by_agent_id)
  end

  def build_call_analysis_events(account, since, until_at, contacts)
    analyses = CallAnalysis.where(account_id: account.id, status: 'completed').where(window(:analyzed_at, since, until_at))
    call_contact = account.calls.where(id: analyses.select(:call_id)).pluck(:id, :contact_id).to_h

    each_safely(account, analyses, 'call_analysis') do |analysis|
      revenue_contact_id = contacts[call_contact[analysis.call_id]]
      upsert_event(account, event_type: 'call_analyzed', event_at: analysis.analyzed_at, source_system: 'call_analysis',
                            source_id: analysis.id.to_s, revenue_contact_id: revenue_contact_id, call_id: analysis.call_id,
                            agent_id: analysis.agent_id, metadata: call_analysis_metadata(analysis))
    end
  end

  def call_analysis_metadata(analysis)
    { 'score' => analysis.total_score, 'intent_level' => analysis.intent_level, 'confidence' => analysis.confidence }
  end

  def build_lead_events(account, since, until_at)
    leads = account.revenue_leads.where(window(:updated_at, since, until_at))

    each_safely(account, leads, 'lead') do |lead|
      upsert_lead_milestone(account, lead, 'lead_created', lead.created_at_source)
      upsert_lead_milestone(account, lead, 'lead_contacted', lead.first_contact_at)
      upsert_lead_milestone(account, lead, 'lead_qualified', lead.qualified_at)
    end
  end

  def upsert_lead_milestone(account, lead, event_type, event_at)
    return if event_at.blank?

    upsert_event(account, event_type: event_type, event_at: event_at, source_system: 'revenue_lead',
                          source_id: lead.id.to_s, revenue_contact_id: lead.revenue_contact_id, zoho_lead_id: lead.zoho_lead_id)
  end

  def build_deal_events(account, since, until_at)
    deals = account.revenue_deals.where(window(:updated_at, since, until_at))

    each_safely(account, deals, 'deal') do |deal|
      next if deal.created_at_source.blank?

      upsert_event(account, event_type: 'deal_created', event_at: deal.created_at_source, source_system: 'revenue_deal',
                            source_id: deal.id.to_s, revenue_contact_id: deal.revenue_contact_id, zoho_deal_id: deal.zoho_deal_id,
                            zoho_lead_id: deal.revenue_lead&.zoho_lead_id)
    end
  end

  def build_stage_events(account, since, until_at)
    stage_events = account.revenue_stage_events.where(window(:created_at, since, until_at))

    each_safely(account, stage_events, 'stage_event') do |stage_event|
      upsert_event(account, event_type: 'stage_changed', event_at: stage_event.entered_at, source_system: 'revenue_stage_event',
                            source_id: stage_event.id.to_s, revenue_contact_id: stage_event.revenue_contact_id,
                            zoho_deal_id: stage_event.zoho_deal_id,
                            metadata: { 'stage' => stage_event.stage, 'previous_stage' => stage_event.previous_stage })

      classify_stage_outcome(account, stage_event)
    end
  end

  # Un stage puede calificar para MÁS de un tipo a la vez (ej. si algún día aparece un valor
  # huérfano que sea simultáneamente "visita efectiva" y "ganado") — nunca es elsif, cada
  # clasificación se evalúa independiente. Mismas listas/constantes ya usadas en Fase 1 y en
  # V2::Reports::SalesFunnelBuilder — no se inventa una nueva.
  def classify_stage_outcome(account, stage_event)
    stage = stage_event.stage
    stage_outcome_types(stage).each do |event_type|
      upsert_event(account, event_type: event_type, event_at: stage_event.entered_at, source_system: 'revenue_stage_event',
                            source_id: stage_event.id.to_s, revenue_contact_id: stage_event.revenue_contact_id,
                            zoho_deal_id: stage_event.zoho_deal_id)
    end
  end

  def stage_outcome_types(stage)
    [
      ('visit_effective' if V2::Reports::SalesFunnelBuilder::VISITA_EFECTIVA_STAGES.include?(stage)),
      ('reserved' if stage == RevenueDeal::RESERVED_STAGE),
      ('closed_won' if stage == RevenueDeal::WON_STAGE),
      ('closed_lost' if stage == RevenueDeal::LOST_STAGE)
    ].compact
  end

  def build_appointment_events(account, since, until_at)
    appointments = account.revenue_appointments.where(window(:created_at, since, until_at))

    each_safely(account, appointments, 'appointment') do |appointment|
      next if appointment.starts_at.blank?

      upsert_event(account, event_type: 'appointment_created', event_at: appointment.starts_at, source_system: 'revenue_appointment',
                            source_id: appointment.id.to_s, revenue_contact_id: appointment.revenue_contact_id,
                            zoho_deal_id: appointment.zoho_deal_id, zoho_lead_id: appointment.zoho_lead_id)
    end
  end

  # El journey solo tiene sentido para contactos ya resueltos — si no hay revenue_contact_id no se
  # crea el evento (ver comentario de clase sobre el riesgo aceptado de mensajes/llamadas
  # tempranas de identidad todavía no resuelta).
  def upsert_event(account, attrs)
    return if attrs[:revenue_contact_id].blank?

    account.revenue_events.find_or_create_by!(
      source_system: attrs[:source_system], event_type: attrs[:event_type], source_id: attrs[:source_id]
    ) do |event|
      event.assign_attributes(attrs.except(:source_system, :event_type, :source_id))
    end
  end
end
