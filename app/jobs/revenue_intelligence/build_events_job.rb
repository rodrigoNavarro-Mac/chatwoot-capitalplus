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
  # Ver comentario de update_effective_qualified_at.
  QUALIFIED_OR_LATER_STAGES = ([RevenueDeal::SCHEDULED_STAGE] + RevenueDeal::VISIT_STAGES + [RevenueDeal::RESERVED_STAGE,
                                                                                             RevenueDeal::WON_STAGE]).uniq.freeze

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
    end

    update_effective_qualified_at(account)
  end

  # Un lead cuenta como calificado si Zoho trae Fecha_de_calificación llena (qualified_at), O si su
  # deal alcanzó "Agendo cita" o una etapa posterior según Stage_History -- confirmado con el
  # usuario (2026-09-2X) que el equipo de ventas no siempre llena ese campo de Zoho antes de agendar
  # una cita real, así que sin esto "Citas" podía superar a "Calificados" en el funnel, rompiendo su
  # lectura. Mismo principio de "etapa máxima alcanzada" ya aplicado a Contactados
  # (LeadMapper::CONTACTED_LEAD_STATUSES incluye 'Calificado') y a Visitas (RevenueDeal::VISIT_STAGES).
  #
  # Se persiste en una columna PROPIA (revenue_leads.effective_qualified_at), nunca sobreescribiendo
  # qualified_at: ese campo es un mirror crudo de Zoho que LeadMapper reasigna en CADA sync, así que
  # cualquier valor inferido ahí se perdería en la siguiente corrida de SyncZohoLeadsJob.
  #
  # Recalcula TODOS los leads con evidencia (no solo los tocados en la ventana incremental de este
  # run) porque la evidencia vive en revenue_stage_events, que puede cambiar sin que el propio lead
  # se vuelva a tocar -- mismo criterio ya usado en build_visit_effective_events/
  # RefreshAggregatesJob::RECHECK_WINDOW, barato al volumen actual de la cuenta.
  def update_effective_qualified_at(account)
    inferred = inferred_qualification_lookup(account)
    leads = account.revenue_leads.where.not(qualified_at: nil).or(account.revenue_leads.where(id: inferred.keys))

    leads.find_each do |lead|
      effective = [lead.qualified_at, inferred[lead.id]].compact.min
      # rubocop:disable Rails/SkipsModelValidations
      lead.update_columns(effective_qualified_at: effective) if lead.effective_qualified_at != effective
      # rubocop:enable Rails/SkipsModelValidations
      upsert_lead_milestone(account, lead, 'lead_qualified', effective)
    end
  end

  # { revenue_lead_id => fecha MÁS ANTIGUA en la que su deal alcanzó QUALIFIED_OR_LATER_STAGES }
  def inferred_qualification_lookup(account)
    deal_lead_id_by_zoho = account.revenue_deals.where.not(revenue_lead_id: nil).pluck(:zoho_deal_id, :revenue_lead_id).to_h

    account.revenue_stage_events.where(stage: QUALIFIED_OR_LATER_STAGES).where.not(zoho_deal_id: nil)
           .pluck(:zoho_deal_id, :entered_at).each_with_object({}) do |(zoho_deal_id, entered_at), lookup|
      lead_id = deal_lead_id_by_zoho[zoho_deal_id]
      next unless lead_id

      lookup[lead_id] = [lookup[lead_id], entered_at].compact.min
    end
  end

  # Si event_at ya no tiene valor (el campo de origen se limpió DESPUÉS de que el evento ya
  # existía — confirmado en producción con un lead cuyo first_contact_at volvió a nil), el evento
  # viejo se BORRA en vez de dejarse huérfano -- sin esto, un evento con event_at desde antes de
  # la limpieza sigue contando en los rollups de tipo funnel para siempre, aunque
  # campaign/lead_source (que leen el campo actual, ya nil) ya no lo cuenten. Mismo bug de fondo
  # que el fix de upsert_event (event_at nunca se refrescaba), en su variante "el dato desapareció"
  # en vez de "el dato cambió".
  def upsert_lead_milestone(account, lead, event_type, event_at)
    key = { source_system: 'revenue_lead', event_type: event_type, source_id: lead.id.to_s }
    return delete_event(account, key) if event_at.blank?

    upsert_event(account, key.merge(event_at: event_at, revenue_contact_id: lead.revenue_contact_id, zoho_lead_id: lead.zoho_lead_id))
  end

  def build_deal_events(account, since, until_at)
    deals = account.revenue_deals.where(window(:updated_at, since, until_at))

    each_safely(account, deals, 'deal') do |deal|
      key = { source_system: 'revenue_deal', event_type: 'deal_created', source_id: deal.id.to_s }
      next delete_event(account, key) if deal.created_at_source.blank?

      upsert_event(account, key.merge(event_at: deal.created_at_source, revenue_contact_id: deal.revenue_contact_id,
                                      zoho_deal_id: deal.zoho_deal_id, zoho_lead_id: deal.revenue_lead&.zoho_lead_id))
    end
  end

  def delete_event(account, key)
    account.revenue_events.where(key).delete_all
  end

  def build_stage_events(account, since, until_at)
    # :updated_at, no :created_at — igual que build_lead_events/build_deal_events. Una fila de
    # stage_event conserva su created_at original aunque StageHistoryBuilder la reescriba en una
    # corrida posterior (find_or_initialize_by + save!, ver SyncZohoStageHistoryJob); filtrar por
    # created_at hace que un hueco de ventana entre cursores sea PERMANENTE (nunca se autosana),
    # a diferencia de leads/deals que se re-capturan solos en cuanto se vuelven a tocar.
    stage_events = account.revenue_stage_events.where(window(:updated_at, since, until_at))
    # Deals con una cita YA verificada por un Zoho Event real (ver revenue_appointment.rb) — para
    # esos no se emite la señal débil por stage, así "Citas" no cuenta dos veces la misma cita.
    verified_deal_ids = account.revenue_appointments.where.not(zoho_deal_id: nil).distinct.pluck(:zoho_deal_id).to_set

    each_safely(account, stage_events, 'stage_event') do |stage_event|
      upsert_event(account, event_type: 'stage_changed', event_at: stage_event.entered_at, source_system: 'revenue_stage_event',
                            source_id: stage_event.id.to_s, revenue_contact_id: stage_event.revenue_contact_id,
                            zoho_deal_id: stage_event.zoho_deal_id,
                            metadata: { 'stage' => stage_event.stage, 'previous_stage' => stage_event.previous_stage })

      classify_stage_outcome(account, stage_event)
    end

    build_visit_effective_events(account)
    build_appointment_created_from_stage_events(account, verified_deal_ids)
  end

  # Un stage puede calificar para MÁS de un tipo a la vez (ej. Apartado es simultáneamente "visita
  # efectiva" y "reserved") — nunca es elsif, cada clasificación se evalúa independiente.
  # RevenueDeal::VISIT_STAGES (no V2::Reports::SalesFunnelBuilder::VISITA_EFECTIVA_STAGES, que usa
  # una representación en inglés de otra fuente — ver comentario en el modelo). 'visit_effective' y
  # 'appointment_created' por stage NO se clasifican aquí -- ver build_visit_effective_events y
  # build_appointment_created_from_stage_events, deduplicados aparte por deal (ver su comentario).
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
      ('reserved' if stage == RevenueDeal::RESERVED_STAGE),
      ('closed_won' if stage == RevenueDeal::WON_STAGE),
      ('closed_lost' if stage == RevenueDeal::LOST_STAGE)
    ].compact
  end

  # 'visit_effective' deduplicado a UN evento por deal -- a diferencia de los outcomes de
  # stage_outcome_types (cada uno atado a un único stage puntual), RevenueDeal::VISIT_STAGES tiene
  # 4 stages distintos (Visita efectiva, Cotizado, Apartado, Cerrado ganado) que un mismo deal
  # atraviesa en su progresión normal. Clasificarlo inline por cada stage_event (como antes)
  # generaba hasta 4 eventos 'visit_effective' para el MISMO deal, inflando "Visitas" del embudo
  # más allá del número real de deals con visita — bug real encontrado 2026-09-21 al construir el
  # funnel de Marketing por anuncio (ver RevenueIntelligence::RefreshAggregatesJob#earliest_visit_by_deal,
  # que ya evitaba este mismo problema para los rollups de marketing). Recalcula TODOS los deals
  # con algún stage_event calificado en cada corrida (no solo los tocados en la ventana incremental)
  # -- barato al volumen actual de la cuenta, evita depender de una ventana para autosanarse, mismo
  # criterio que RefreshAggregatesJob::RECHECK_WINDOW.
  def build_visit_effective_events(account)
    qualifying = account.revenue_stage_events.where(stage: RevenueDeal::VISIT_STAGES).where.not(revenue_deal_id: nil)
    earliest_at_by_deal = qualifying.group(:revenue_deal_id).minimum(:entered_at)
    return if earliest_at_by_deal.empty?

    attrs_by_deal = qualifying.pluck(:revenue_deal_id, :zoho_deal_id, :revenue_contact_id)
                              .each_with_object({}) { |(deal_id, zoho_deal_id, contact_id), h| h[deal_id] ||= [zoho_deal_id, contact_id] }

    earliest_at_by_deal.each do |deal_id, entered_at|
      zoho_deal_id, revenue_contact_id = attrs_by_deal[deal_id]
      upsert_event(account, event_type: 'visit_effective', event_at: entered_at, source_system: 'revenue_stage_event',
                            source_id: "deal:#{deal_id}", revenue_contact_id: revenue_contact_id, zoho_deal_id: zoho_deal_id)
    end
  end

  # 'appointment_created' por stage (señal débil: el deal entró a "Agendo cita" en Zoho, sin que
  # necesariamente exista un Zoho Event/Meeting real sincronizado -- confirmado con el usuario que
  # para esta cuenta ESTA es la fuente de verdad de "hubo cita", el sync de Meetings vía Zoho casi
  # no trae datos reales) deduplicado a UN evento por deal, con el mismo criterio de "etapa máxima
  # alcanzada" que ya usa build_visit_effective_events -- QUALIFIED_OR_LATER_STAGES es Agendo cita
  # UNION VISIT_STAGES: un deal cuyo historial de stage_events sincronizado desde Zoho SALTA
  # directo a Visita efectiva/Cotizado/Apartado/Cerrado ganado (sin una fila explícita de "Agendo
  # cita" -- pasa cuando el registro de Zoho no capturó esa transición puntual) también cuenta como
  # "tuvo cita". Bug real confirmado 2026-09-23: solo se emitía si stage == SCHEDULED_STAGE
  # exacto, así que deals ya avanzados a etapas posteriores sin ese stage_event puntual quedaban
  # sin contar en "Citas" aunque el embudo ya los mostrara en Visitas.
  def build_appointment_created_from_stage_events(account, verified_deal_ids)
    qualifying = account.revenue_stage_events.where(stage: QUALIFIED_OR_LATER_STAGES).where.not(revenue_deal_id: nil)
                        .where.not(zoho_deal_id: verified_deal_ids.to_a)
    earliest_at_by_deal = qualifying.group(:revenue_deal_id).minimum(:entered_at)
    return if earliest_at_by_deal.empty?

    attrs_by_deal = qualifying.pluck(:revenue_deal_id, :zoho_deal_id, :revenue_contact_id)
                              .each_with_object({}) { |(deal_id, zoho_deal_id, contact_id), h| h[deal_id] ||= [zoho_deal_id, contact_id] }

    earliest_at_by_deal.each do |deal_id, entered_at|
      zoho_deal_id, revenue_contact_id = attrs_by_deal[deal_id]
      upsert_event(account, event_type: 'appointment_created', event_at: entered_at, source_system: 'revenue_stage_event',
                            source_id: "deal:#{deal_id}", revenue_contact_id: revenue_contact_id, zoho_deal_id: zoho_deal_id)
    end
  end

  # "Citas" es un hito del embudo (¿este deal/lead YA TIENE una reunión agendada?, sin importar si
  # la reunión en sí ya pasó) — no se ancla a `starts_at` (la fecha/hora real de la reunión, que
  # puede caer en el futuro respecto al momento del sync) sino a `created_at` (cuándo Chatwoot se
  # enteró de que la cita existe) — mismo criterio que ya usa la señal débil por stage
  # (stage_event.entered_at: cuándo se alcanzó el hito, no una fecha futura). Bug real confirmado
  # 2026-09-21: una cita real agendada para una hora que todavía no llegaba no contaba en "Citas"
  # del periodo actual aunque el deal ya la tuviera confirmada -- internamente Fuego cuenta "ya
  # tiene cita" desde que se agenda, no desde que ocurre.
  #
  # Un mismo deal puede tener más de un Meeting real en Zoho (reagendado, o una segunda cita de
  # seguimiento), así que se deduplica a UN evento por entidad (deal si tiene zoho_deal_id, si no
  # por zoho_lead_id), usando el registro MÁS ANTIGUO por created_at (cuándo se alcanzó el hito por
  # primera vez). Bug real confirmado 2026-09-17: un deal con 2 Meetings reales (uno capturado
  # cuando el registro todavía era Lead, sin zoho_deal_id, y otro ya ligado al Deal tras la
  # conversión) generaba 2 eventos appointment_created, inflando "Citas" del Overview más allá del
  # número real de deals con cita.
  def build_appointment_events(account, since, until_at)
    # :updated_at, mismo razonamiento que build_stage_events arriba.
    touched = account.revenue_appointments.where(window(:updated_at, since, until_at))
    entity_keys = touched.filter_map { |appointment| appointment_entity_key(appointment) }.uniq

    entity_keys.each { |key_type, key_value| upsert_appointment_created_event(account, key_type, key_value) }
  end

  def appointment_entity_key(appointment)
    return [:deal, appointment.zoho_deal_id] if appointment.zoho_deal_id.present?
    return [:lead, appointment.zoho_lead_id] if appointment.zoho_lead_id.present?

    nil
  end

  def upsert_appointment_created_event(account, key_type, key_value)
    scope = if key_type == :deal
              account.revenue_appointments.where(zoho_deal_id: key_value)
            else
              account.revenue_appointments.where(zoho_deal_id: nil, zoho_lead_id: key_value)
            end
    earliest = scope.where.not(starts_at: nil).order(:created_at).first
    key = { source_system: 'revenue_appointment', event_type: 'appointment_created', source_id: "#{key_type}:#{key_value}" }

    return delete_event(account, key) if earliest.nil?

    upsert_event(account, key.merge(event_at: earliest.created_at, revenue_contact_id: earliest.revenue_contact_id,
                                    zoho_deal_id: earliest.zoho_deal_id, zoho_lead_id: earliest.zoho_lead_id))
  end

  # El journey solo tiene sentido para contactos ya resueltos — si no hay revenue_contact_id no se
  # crea el evento (ver comentario de clase sobre el riesgo aceptado de mensajes/llamadas
  # tempranas de identidad todavía no resuelta).
  #
  # find_or_initialize_by + save! si cambió (no find_or_create_by!, que es create-only): un evento
  # ya creado antes SÍ puede necesitar su event_at/metadata actualizados en una corrida posterior
  # -- ej. lead_contacted usa revenue_leads.first_contact_at, que la corrección de "primer contacto
  # real" (backfill_first_contact_time.rake) reescribe DESPUÉS de que el evento original ya existía;
  # igual con stage_changed/closed_won/etc. si StageHistoryBuilder reescribe entered_at en una
  # corrida posterior (ver comentario de build_stage_events). Con find_or_create_by! ese evento
  # quedaba con el event_at viejo para siempre, aunque el dato de origen ya estuviera corregido --
  # bug real confirmado en producción (funnel de agosto 2026: 277 lead_contacted vía revenue_events
  # vs. 341 vía campaign+lead_source, que leen first_contact_at directo).
  def upsert_event(account, attrs)
    return if attrs[:revenue_contact_id].blank?

    event = account.revenue_events.find_or_initialize_by(
      source_system: attrs[:source_system], event_type: attrs[:event_type], source_id: attrs[:source_id]
    )
    event.assign_attributes(attrs.except(:source_system, :event_type, :source_id))
    event.save! if event.new_record? || event.changed?
  end
end
