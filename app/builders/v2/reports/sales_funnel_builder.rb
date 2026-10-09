# Arma el embudo de ventas por desarrollo, leyendo de las MISMAS tablas que Marketing/Overview de
# Revenue Intelligence (revenue_events/revenue_rollups, vía V2::Reports::RevenueIntelligenceBuilder)
# -- antes este builder contaba a partir de conversaciones de Chatwoot + campos de Zoho cacheados
# en el contacto (additional_attributes), agrupado por inbox de WhatsApp, lo que daba números
# distintos a Marketing/Overview para el "mismo" lead (un lead que nunca escribió por WhatsApp no
# existía aquí aunque sí existiera en Zoho). Unificado 2026-10-09 a pedido explícito: los 3 embudos
# de ventas deben mostrar exactamente la misma información, con el mismo formato.
#
# SEQUENCE es un subconjunto de RevenueIntelligence::RefreshAggregatesJob::FUNNEL_EVENT_TYPES --
# las 5 etapas que ya mostraba este reporte, ahora con los nombres canónicos que usan Marketing/
# Overview (antes: leads/customer_replied/has_deal/visita_efectiva/closed_won). El % de cada etapa
# es sobre la etapa INMEDIATA anterior DE ESTA SECUENCIA (no de la secuencia completa de Overview),
# igual criterio que el embudo clásico de conversión escalonada que ya tenía este reporte antes del
# 2026-08-19 (ver comentario histórico más abajo en #stage_row).
class V2::Reports::SalesFunnelBuilder
  include DateRangeHelper

  SEQUENCE = %w[lead_created lead_contacted deal_created visit_effective closed_won].freeze

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    desarrollos.map { |desarrollo| build_row(desarrollo) }
  end

  private

  # Mismo universo que RevenueIntelligenceBuilder#available_desarrollos (todo el histórico, no solo
  # el rango de fechas elegido) -- para que el selector de desarrollo de este reporte liste las
  # mismas opciones que el de Overview/Marketing. params[:desarrollo] (si viene) acota a uno solo.
  def desarrollos
    all = account.revenue_rollups.where.not(desarrollo: '_all').distinct.order(:desarrollo).pluck(:desarrollo)
    params[:desarrollo].present? ? all.select { |d| d == params[:desarrollo] } : all
  end

  def build_row(desarrollo)
    {
      development_key: desarrollo,
      stages: revenue_intelligence_builder(desarrollo).funnel_steps(SEQUENCE).map { |step| stage_row(step, desarrollo) },
      calls: calls_metric(desarrollo)
    }
  end

  # Una instancia de RevenueIntelligenceBuilder POR DESARROLLO -- #funnel_steps ya resuelve
  # count/conversion_from_previous/seguimiento_count/lost_count scopeados a este desarrollo (ver
  # RevenueIntelligenceBuilder#funnel_totals, respeta desarrollo_filter), así que este builder no
  # recalcula nada, solo reempaqueta.
  def revenue_intelligence_builder(desarrollo)
    V2::Reports::RevenueIntelligenceBuilder.new(account: account, params: params.merge(desarrollo: desarrollo))
  end

  # actual_percent como porcentaje (0-100, no fracción) para que FunnelStageMeter/el marcador de
  # meta lo consuman directo -- conversion_from_previous de #funnel_steps es nil solo en la primera
  # etapa (sin "anterior"), que siempre se muestra 100% (ella misma es su propia base), igual
  # criterio que ya usan Overview/Marketing en el frontend (`step.conversion ?? 1`).
  def stage_row(step, desarrollo)
    target = goal_for(desarrollo, step[:metric])
    actual_percent = ((step[:conversion_from_previous] || 1.0) * 100).round(2)

    { stage: step[:metric], count: step[:count], seguimiento_count: step[:seguimiento_count], lost_count: step[:lost_count],
      actual_percent: actual_percent, target_percent: target, delta: target.nil? ? nil : (actual_percent - target).round(2) }
  end

  # Total de llamadas de Aircall y % contestadas de TODOS los inboxes de WhatsApp ligados a este
  # desarrollo (antes era una fila por inbox; ver comentario de clase) -- "contestada" es
  # status == 'completed', el único valor que Crm::Aircall::CallProcessor asigna a una llamada que
  # sí tuvo answered_at (ver app/services/crm/aircall/call_processor.rb).
  def calls_metric(desarrollo)
    scope = account.calls.aircall.where(inbox_id: inbox_ids_for_desarrollo(desarrollo))
    scope = scope.where(started_at: range) if range.present?
    total = scope.count
    answered = scope.where(status: 'completed').count

    { total: total, answered: answered, answered_percent: percent(answered, total) }
  end

  def inbox_ids_for_desarrollo(desarrollo)
    account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(agent_bot_inbox: :agent_bot)
           .select { |inbox| development_key_for(inbox) == desarrollo }.map(&:id)
  end

  def development_key_for(inbox)
    inbox.agent_bot&.bot_config&.dig('variables', 'desarrollo')
  end

  def goal_for(desarrollo, stage)
    return nil if period_start.nil?

    goals_by_key[[desarrollo, stage]]
  end

  # La meta configurada para un desarrollo/etapa queda vigente hasta que se capture una nueva — no
  # hace falta recapturar el mismo valor cada mes. Por cada (development_key, stage), usa la meta
  # con el period_month más reciente que sea <= el mes del reporte (nunca una futura).
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

  def percent(numerator, denominator)
    return 0.0 if denominator.to_i.zero?

    (numerator.to_f / denominator * 100).round(2)
  end
end
