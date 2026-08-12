# Arma el embudo de ventas por entrada (inbox de WhatsApp) y desarrollo:
#   leads totales -> contestados por el cliente -> con deal en Zoho -> visita efectiva ->
#   deal cerrado ganado
#
# Cada etapa es subconjunto de la anterior (igual que un embudo real), y el % de cada etapa se
# calcula sobre el total de leads de esa misma entrada. El "desarrollo" de una entrada es el que
# ya usa el resto del sistema Zoho (agent_bot.bot_config['variables']['desarrollo'], ver
# Api::V1::Accounts::Integrations::ZohoCrmController#bot_variables_for). El estado del deal
# (existe / visita efectiva / cerrado ganado) se lee de additional_attributes['external'] en el
# contacto, cacheado por Crm::Zoho::DealsSyncJob (o por ZohoCrmController#create_deal al crearlo
# desde Chatwoot).
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

    leads = leads_with_zoho_link(first_conversation_pairs(inbox))
    replied = customer_replied(leads)
    with_deal = pairs_with_deal(replied)
    visited = visita_efectiva(with_deal)
    won = closed_won(visited)

    {
      inbox_id: inbox.id,
      inbox_name: inbox.name,
      development_key: development_key,
      stages: [
        stage_metric('leads', leads.size, leads.size, development_key),
        stage_metric('customer_replied', replied.size, leads.size, development_key),
        stage_metric('has_deal', with_deal.size, leads.size, development_key),
        stage_metric('visita_efectiva', visited.size, leads.size, development_key),
        stage_metric('closed_won', won.size, leads.size, development_key)
      ],
      calls: calls_metric(inbox)
    }
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

  def leads_with_zoho_link(pairs)
    filter_pairs_by_contact(pairs, "additional_attributes -> 'external' ->> 'zoho_id' IS NOT NULL")
  end

  def customer_replied(pairs)
    return [] if pairs.empty?

    conversation_ids = pairs.map(&:first)
    replied_ids = Message.where(conversation_id: conversation_ids, message_type: :incoming)
                         .pluck(:conversation_id).to_set

    pairs.select { |(conversation_id, _contact_id)| replied_ids.include?(conversation_id) }
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

  def filter_pairs_by_contact(pairs, sql_condition)
    return [] if pairs.empty?

    matching_ids = Contact.where(id: pairs.map(&:last)).where(sql_condition).pluck(:id).to_set
    pairs.select { |(_conversation_id, contact_id)| matching_ids.include?(contact_id) }
  end

  def stage_metric(stage, count, leads_count, development_key)
    target = goal_for(development_key, stage)
    actual_percent = safe_rate(count, leads_count)

    {
      stage: stage,
      count: count,
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
