# Arma el embudo de ventas por entrada (inbox de WhatsApp) y desarrollo:
#   leads totales -> contestados por el cliente -> con deal en Zoho -> visita efectiva ->
#   deal cerrado ganado
#
# Cada etapa es subconjunto de la anterior (igual que un embudo real), y el % de cada etapa se
# calcula sobre la etapa INMEDIATA anterior, no sobre el total de leads (embudo clásico de
# conversión escalonada) — "leads" es la excepción obvia (100% de sí misma), y "customer_replied"
# coincide con "% del total" porque su etapa anterior ya es "leads". Antes del 2026-08-19 todas las
# etapas usaban el total de leads como base, lo que hacía que "% Visita efectiva" se leyera como
# "2 de 70 leads totales" en vez de "2 de 5 leads con deal" — la pregunta que en realidad responde
# esa etapa del embudo. El "desarrollo" de una entrada es el que
# ya usa el resto del sistema Zoho (agent_bot.bot_config['variables']['desarrollo'], ver
# Api::V1::Accounts::Integrations::ZohoCrmController#bot_variables_for). El estado del deal
# (existe / visita efectiva / cerrado ganado) se lee de additional_attributes['external'] en el
# contacto, cacheado por Crm::Zoho::DealsSyncJob (o por ZohoCrmController#create_deal al crearlo
# desde Chatwoot).
#
# has_deal/visita_efectiva/closed_won le suman a `count` (y por lo tanto al % y al cumplimiento de
# meta) la actividad de deals CREADOS en el periodo que no vienen de la cohorte de "leads nuevos"
# (ver #deal_activity_outside_cohort) — sin esto, un deal real creado esta semana de un lead que
# llegó antes nunca movía el % ni contaba para la meta, aunque existiera y se viera en Zoho (caso
# real detectado 2026-08-24). Esa porción extra viaja aparte en `activity_count` de cada stage para
# que el frontend la pinte en otro color dentro de la misma barra, en vez de mezclarse en un solo
# número sin distinguir cohorte de actividad.
class V2::Reports::SalesFunnelBuilder
  include DateRangeHelper

  # Valores internos ("actual_value") del campo Stage en el pipeline de Deals de Zoho de esta
  # cuenta — NO son los labels en español que se ven en la UI de Zoho (que están traducidos).
  # Confirmado contra la API real: "Visita efectiva - Videollamada" -> Qualification, "Cotizado
  # con visita" -> Needs Analysis, "Apartado" -> Id. Decision Makers, "Cerrado ganado" -> Closed Won.
  #
  # El picklist de Stage en este Zoho tiene historial de valores "huérfanos" — opciones que
  # existieron con un actual_value propio antes de que se renombraran/consolidaran, pero deals
  # viejos siguen cargando el valor original en vez del nuevo (confirmado con un caso real: un
  # deal con Stage = "Visita efectiva" a secas, que ya no aparece como opción del picklist actual,
  # en vez de "Qualification"). Por eso la lista incluye ambos valores por etapa donde se conoce
  # un huérfano — no hay forma de anticipar todos los que puedan existir, así que si aparece un
  # caso nuevo hay que agregarlo aquí.
  VISITA_EFECTIVA_STAGES = [
    'Qualification', 'Visita efectiva',
    'Needs Analysis',
    'Id. Decision Makers', 'Identify Decision Makers',
    'Closed Won'
  ].freeze
  CLOSED_WON_STAGES = ['Closed Won'].freeze
  STAGES = %w[leads customer_replied has_deal visita_efectiva closed_won].freeze

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    target_inboxes.map { |inbox| build_row(inbox) }
  end

  private

  def target_inboxes
    scope = account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(agent_bot_inbox: :agent_bot)
    scope = scope.where(id: params[:inbox_ids]) if params[:inbox_ids].present?
    scope.select { |inbox| development_key_for(inbox).present? }
  end

  def development_key_for(inbox)
    inbox.agent_bot&.bot_config&.dig('variables', 'desarrollo')
  end

  def build_row(inbox)
    development_key = development_key_for(inbox)

    {
      inbox_id: inbox.id,
      inbox_name: inbox.name,
      development_key: development_key,
      stages: funnel_stages(funnel_pairs(inbox), development_key),
      calls: calls_metric(inbox)
    }
  end

  def funnel_pairs(inbox)
    zoho_linked = leads_with_zoho_link(first_conversation_pairs(inbox))
    leads, reactivated = partition_new_vs_reactivated(zoho_linked)
    replied = customer_replied(leads)
    with_deal = pairs_with_deal(replied)
    visited = visita_efectiva(with_deal)
    won = closed_won(visited)

    { leads: leads, reactivated: reactivated, replied: replied, with_deal: with_deal, visited: visited, won: won }
  end

  def funnel_stages(pairs, development_key)
    extra = deal_activity_outside_cohort(development_key, pairs[:with_deal].to_set(&:last))
    counts = combined_counts(pairs, extra)

    stage_definitions(pairs, counts, extra).map do |stage, count, base_count, breakdown|
      stage_metric(stage, count, base_count, development_key, breakdown: breakdown)
    end
  end

  # `count` combinado (cohorte + actividad fuera de cohorte + externos) por etapa — ver
  # #deal_activity_outside_cohort para el porqué de sumarlos.
  def combined_counts(pairs, extra)
    {
      has_deal: pairs[:with_deal].size + extra[:has_deal] + extra[:external],
      visita_efectiva: pairs[:visited].size + extra[:visita_efectiva] + extra[:external_visita_efectiva],
      closed_won: pairs[:won].size + extra[:closed_won] + extra[:external_closed_won]
    }
  end

  # [stage, count, base_count, breakdown] por etapa — "leads" lleva `reactivated_count` (ver
  # #partition_new_vs_reactivated); "customer_replied" no tiene equivalente de actividad/externos/
  # reactivados (breakdown vacío), ver #deal_activity_outside_cohort.
  def stage_definitions(pairs, counts, extra)
    [
      ['leads', pairs[:leads].size, pairs[:leads].size, { reactivated_count: pairs[:reactivated].size }],
      ['customer_replied', pairs[:replied].size, pairs[:leads].size, {}],
      ['has_deal', counts[:has_deal], pairs[:replied].size, { activity_count: extra[:has_deal], external_count: extra[:external] }],
      ['visita_efectiva', counts[:visita_efectiva], counts[:has_deal],
       { activity_count: extra[:visita_efectiva], external_count: extra[:external_visita_efectiva] }],
      ['closed_won', counts[:closed_won], counts[:visita_efectiva],
       { activity_count: extra[:closed_won], external_count: extra[:external_closed_won] }]
    ]
  end

  # Deals de Zoho CREADOS en el periodo que no vienen de la cohorte de "leads nuevos del periodo"
  # (`with_deal_contact_ids`) — ver V2::Reports::SalesFunnelDealActivity para el porqué (caso real
  # detectado 2026-08-24/25). Se suma al `count`/`%`/meta de has_deal, visita_efectiva y closed_won
  # (ver #build_row) para que un deal real de este periodo sí mueva la aguja, sin contar dos veces lo
  # que la cohorte ya cuenta.
  def deal_activity_outside_cohort(development_key, with_deal_contact_ids)
    deal_activity.outside_cohort(development_key, with_deal_contact_ids)
  end

  def deal_activity
    @deal_activity ||= V2::Reports::SalesFunnelDealActivity.new(account: account, range: range)
  end

  # Total de llamadas de Aircall del inbox en el periodo y % contestadas — "contestada" es
  # status == 'completed', el único valor que Crm::Aircall::CallProcessor asigna a una llamada
  # que sí tuvo answered_at (ver app/services/crm/aircall/call_processor.rb).
  def calls_metric(inbox)
    scope = account.calls.aircall.where(inbox_id: inbox.id)
    scope = scope.where(started_at: range) if range.present?
    total = scope.count
    answered = scope.where(status: 'completed').count

    { total: total, answered: answered, answered_percent: safe_rate(answered, total) }
  end

  # ids (conversation_id, contact_id) de la conversación más antigua de cada contacto de la
  # cuenta, restringidos a las que caen en este inbox y en el rango de fechas — así un contacto
  # solo puede aparecer como "lead" de la entrada donde realmente entró por primera vez.
  def first_conversation_pairs(inbox)
    scope = Conversation.where(id: earliest_conversation_ids, inbox_id: inbox.id)
    scope = scope.where(created_at: range) if range.present?
    scope.pluck(:id, :contact_id)
  end

  def earliest_conversation_ids
    sql = <<~SQL.squish
      SELECT DISTINCT ON (contact_id) id FROM conversations
      WHERE account_id = :account_id AND contact_id IS NOT NULL
      ORDER BY contact_id, created_at ASC
    SQL
    ActiveRecord::Base.connection.select_values(
      ActiveRecord::Base.sanitize_sql_array([sql, { account_id: account.id }])
    )
  end

  ZOHO_LINK_SQL = "additional_attributes -> 'external' ->> 'zoho_id' IS NOT NULL".freeze

  # Ver V2::Reports::SalesFunnelZohoIdDedupe (separada de esta clase solo por tamaño) — dos
  # contactos de Chatwoot pueden compartir el mismo zoho_id, y sin el dedupe se contaba dos veces.
  def leads_with_zoho_link(pairs)
    V2::Reports::SalesFunnelZohoIdDedupe.new.dedupe(filter_pairs_by_contact(pairs, ZOHO_LINK_SQL))
  end

  # [nuevos, reactivados] — ver V2::Reports::SalesFunnelReactivatedLeads (separada de esta clase solo
  # por tamaño, mismo criterio que SalesFunnelDealActivity).
  def partition_new_vs_reactivated(pairs)
    V2::Reports::SalesFunnelReactivatedLeads.new(range: range).partition(pairs)
  end

  # "Contestó" no es solo un mensaje incoming (WhatsApp, o una llamada que el cliente hizo) — una
  # llamada SALIENTE (el asesor llamó al cliente) que el cliente contestó (Call#status ==
  # 'completed') es la misma señal de engagement real, aunque el Message que crea
  # Voice::CallMessageBuilder para esa llamada quede como outgoing (ver
  # Crm::Aircall::CallProcessor). Caso real que detectó este hueco: deal en "Visita efectiva -
  # Videollamada" cuyas 4 llamadas eran todas salientes contestadas (una de 379s) — customer_replied
  # daba false porque nunca hubo un Message incoming.
  def customer_replied(pairs)
    return [] if pairs.empty?

    conversation_ids = pairs.map(&:first)
    replied_ids = Message.where(conversation_id: conversation_ids, message_type: :incoming)
                         .pluck(:conversation_id).to_set
    replied_ids.merge(answered_call_conversation_ids(conversation_ids))

    pairs.select { |(conversation_id, _contact_id)| replied_ids.include?(conversation_id) }
  end

  # Call#status == 'completed' NO distingue "contestó una persona" de "contestó el buzón de voz o
  # una contestadora" — Aircall marca answered_at en ambos casos (hallazgo real 2026-09-01: 4
  # llamadas cuya transcripción es un mensaje de buzón de voz, las 4 con status completed). Cuando
  # ya existe un CallAnalysis para la llamada, se usa su lectura de confianza — "low" es justo la
  # señal que ya calcula CallAnalysis::StructuredAnalysisLlmService para "no hubo suficiente
  # interacción real para clasificar con certeza", que es exactamente el caso de un buzón de voz.
  # Si todavía no se analizó, se mantiene el proxy viejo (status completed) para no regresar el
  # hueco que este mismo método arregló el 2026-08-19 (ver comentario de clase).
  def answered_call_conversation_ids(conversation_ids)
    calls = Call.where(conversation_id: conversation_ids, status: 'completed').includes(:call_analysis)

    calls.reject { |call| call.call_analysis&.confidence == 'low' }.to_set(&:conversation_id)
  end

  def pairs_with_deal(pairs)
    filter_pairs_by_contact(pairs, "additional_attributes -> 'external' ->> 'zoho_deal_id' IS NOT NULL")
  end

  def visita_efectiva(pairs)
    return [] if pairs.empty?

    contact_ids = pairs.map(&:last)
    visited_ids = Contact.where(id: contact_ids)
                         .where("additional_attributes -> 'external' ->> 'zoho_deal_stage' IN (?)", VISITA_EFECTIVA_STAGES)
                         .pluck(:id).to_set

    pairs.select { |(_conversation_id, contact_id)| visited_ids.include?(contact_id) }
  end

  def closed_won(pairs)
    return [] if pairs.empty?

    contact_ids = pairs.map(&:last)
    won_ids = Contact.where(id: contact_ids)
                     .where("additional_attributes -> 'external' ->> 'zoho_deal_stage' IN (?)", CLOSED_WON_STAGES)
                     .pluck(:id).to_set

    pairs.select { |(_conversation_id, contact_id)| won_ids.include?(contact_id) }
  end

  def filter_pairs_by_contact(pairs, sql_condition, binds = [])
    return [] if pairs.empty?

    matching_ids = Contact.where(id: pairs.map(&:last)).where(sql_condition, *binds).pluck(:id).to_set
    pairs.select { |(_conversation_id, contact_id)| matching_ids.include?(contact_id) }
  end

  def stage_metric(stage, count, base_count, development_key, breakdown: {})
    target = goal_for(development_key, stage)
    actual_percent = safe_rate(count, base_count)

    {
      stage: stage,
      count: count,
      activity_count: breakdown[:activity_count],
      external_count: breakdown[:external_count],
      reactivated_count: breakdown[:reactivated_count],
      actual_percent: actual_percent,
      target_percent: target,
      delta: target.nil? ? nil : (actual_percent - target).round(2)
    }
  end

  def goal_for(development_key, stage)
    return nil if development_key.blank? || period_start.nil?

    goals_by_key[[development_key, stage]]
  end

  # La meta configurada para un desarrollo/etapa queda vigente hasta que se capture una nueva —
  # no hace falta recapturar el mismo valor cada mes. Por cada (development_key, stage), usa la
  # meta con el period_month más reciente que sea <= el mes del reporte (nunca una futura).
  def goals_by_key
    @goals_by_key ||= account.sales_funnel_goals
                             .where(period_month: ..period_start)
                             .group_by { |goal| [goal.development_key, goal.stage] }
                             .transform_values { |goals| goals.max_by(&:period_month).target_percent.to_f }
  end

  def period_start
    return nil if range.blank?

    range.first.to_date.beginning_of_month
  end

  def safe_rate(numerator, denominator)
    return 0.0 if denominator.to_i.zero?

    (numerator.to_f / denominator * 100).round(2)
  end
end
