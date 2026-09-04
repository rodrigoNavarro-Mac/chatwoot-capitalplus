# Payload único para la página de Revenue Intelligence (Fase 5) — arma TODAS las secciones (una
# por tab de la UI) en una sola respuesta, leyendo exclusivamente de las tablas ya pre-calculadas
# de Fases 3-4 (revenue_rollups/revenue_risk_signals/revenue_lead_journeys), nunca de las tablas
# revenue_* crudas de Fase 1 — mismo principio "la UI no hace joins costosos" ya aplicado en
# CallAnalysisAgentBuilder. Un solo builder para las 8 secciones (no uno por tab) porque el volumen
# de revenue_rollups es pequeño al tamaño actual de la cuenta — ver riesgos del plan de Fase 5.
class V2::Reports::RevenueIntelligenceBuilder
  include DateRangeHelper

  DEFAULT_RANGE_DAYS = 30
  FUNNEL_TREND_METRICS = %w[lead_created appointment_created closed_won].freeze
  # Secuencia real del embudo para calcular conversión etapa-a-etapa — deliberadamente NO incluye
  # 'deal_created' (paralelo al embudo, no un paso obligatorio para el usuario de negocio) ni
  # 'closed_lost' (rama terminal, no un siguiente paso). Mismo orden que
  # RevenueIntelligence::RefreshAggregatesJob::FUNNEL_EVENT_TYPES.
  FUNNEL_SEQUENCE = %w[lead_created lead_contacted lead_qualified appointment_created visit_effective reserved closed_won].freeze

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    totals = funnel_totals
    {
      funnel: rollup_summary('funnel'),
      funnel_totals: totals,
      funnel_conversions: funnel_conversions(totals),
      agent: agent_summary,
      campaign: marketing_hierarchy,
      pipeline_stage: pipeline_stage_summary,
      call_conversion: conversion_summary('call_conversion'),
      objection_conversion: conversion_summary('objection_conversion'),
      risk_signals: risk_signals_summary,
      journeys: journeys_summary,
      funnel_trend: daily_trend(FUNNEL_TREND_METRICS),
      insights: insights
    }
  end

  private

  # DateRangeHelper#range es nil si since/until no vienen en params — se usa un default de 30 días
  # en vez de "todo el histórico", mismo criterio que el filtro por default del frontend existente
  # (CallIntelligenceReport.vue arranca en los últimos 30 días).
  def date_range
    return range.begin.to_date..range.end.to_date if range

    DEFAULT_RANGE_DAYS.days.ago.to_date..Date.current
  end

  def rollups_scope(dimension_type)
    account.revenue_rollups.where(dimension_type: dimension_type, date: date_range)
  end

  # { dimension_id => { metric => count } } — pura agregación Ruby sobre filas ya pequeñas, mismo
  # estilo que V2::Reports::CallAnalysisAgentBuilder#tally.
  def rollup_summary(dimension_type)
    rollups_scope(dimension_type).pluck(:dimension_id, :metric, :count).each_with_object({}) do |(dimension_id, metric, count), acc|
      acc[dimension_id] ||= Hash.new(0)
      acc[dimension_id][metric] += count
    end
  end

  # Igual que rollup_summary('agent') pero además calcula avg_score/cta_rate desde las filas
  # 'calls_scored'/'score_sum'/'cta_used_count' que agent_call_quality_rows agrega aparte de las
  # de actividad de llamadas (call_started/answered/missed) — ambas familias comparten
  # dimension_type 'agent', se combinan aquí en un solo objeto por agente para la UI.
  def agent_summary
    rows = rollups_scope('agent').pluck(:dimension_id, :metric, :count, :sum_value)
    grouped = rows.each_with_object({}) do |(agent_id, metric, count, sum_value), acc|
      acc[agent_id] ||= Hash.new(0)
      acc[agent_id][metric] += count
      acc[agent_id]["#{metric}_value"] += sum_value
    end

    grouped.transform_values { |m| agent_metrics(m) }
  end

  def agent_metrics(metrics)
    calls_scored = metrics['calls_scored']
    {
      'call_started' => metrics['call_started'], 'call_answered' => metrics['call_answered'], 'call_missed' => metrics['call_missed'],
      'calls_scored' => calls_scored,
      'avg_score' => calls_scored.positive? ? (metrics['score_sum_value'] / calls_scored.to_f).round(1) : nil,
      'cta_rate' => calls_scored.positive? ? safe_rate(metrics['cta_used_count'], calls_scored) : nil
    }
  end

  # Reconstruye la jerarquía campaña -> adset -> advert a partir de 3 dimension_types planas de
  # rollups. 'campaign' conserva dimension_id = campaign_id crudo sin tocar (ya tiene datos reales
  # acumulados desde Fase 3, no se puede reescribir su clave sin fragmentar el histórico). 'adset'/
  # 'advert' son dimensiones nuevas cuyo dimension_id trae el nombre embebido (ver
  # RefreshAggregatesJob#marketing_dimension_rows) — se parsean aquí, nunca se lee revenue_leads.
  def marketing_hierarchy
    adsets = rollup_summary('adset')
    adverts = rollup_summary('advert')

    rollup_summary('campaign').map do |campaign_id, metrics|
      { id: campaign_id, metrics: metrics, adsets: marketing_adsets(campaign_id, adsets, adverts) }
    end
  end

  def marketing_adsets(campaign_id, adsets, adverts)
    prefix = "#{campaign_id}::"
    adsets.filter_map do |adset_key, metrics|
      next unless adset_key.start_with?(prefix)

      _campaign_id, adset_id, adset_name = adset_key.split('::', 3)
      { id: adset_id, name: adset_name, metrics: metrics, adverts: marketing_adverts(campaign_id, adset_id, adverts) }
    end
  end

  def marketing_adverts(campaign_id, adset_id, adverts)
    prefix = "#{campaign_id}::#{adset_id}::"
    adverts.filter_map do |advert_key, metrics|
      next unless advert_key.start_with?(prefix)

      _campaign_id, _adset_id, advert_id, advert_name = advert_key.split('::', 4)
      { id: advert_id, name: advert_name, metrics: metrics }
    end
  end

  # avg_duration_days: sum_value (segundos) / count de la fila 'duration_seconds' — nil si todavía
  # no hay filas cerradas para ese stage en el rango (ver RefreshAggregatesJob#pipeline_stage_rows).
  def pipeline_stage_summary
    rows = rollups_scope('pipeline_stage').pluck(:dimension_id, :metric, :count, :sum_value)

    rows.each_with_object({}) do |(stage, metric, count, sum_value), acc|
      acc[stage] ||= { 'entered' => 0, 'avg_duration_days' => nil }
      if metric == 'entered'
        acc[stage]['entered'] += count
      elsif count.positive?
        acc[stage]['avg_duration_days'] = (sum_value.to_f / count / 1.day).round(1)
      end
    end
  end

  # { dimension_id => { total:, converted:, rate: } } — dimension_id ya trae la clave compuesta
  # (ej. "cta_used:true") escrita por RefreshAggregatesJob, no se reconstruye aquí.
  def conversion_summary(dimension_type)
    rows = rollups_scope(dimension_type).pluck(:dimension_id, :metric, :count)

    grouped = rows.each_with_object({}) do |(dimension_id, metric, count), acc|
      acc[dimension_id] ||= { 'total' => 0, 'converted' => 0 }
      acc[dimension_id][metric] += count
    end
    grouped.transform_values { |row| row.merge('rate' => safe_rate(row['converted'], row['total'])) }
  end

  def safe_rate(numerator, denominator)
    return 0.0 if denominator.to_i.zero?

    (numerator.to_f / denominator).round(4)
  end

  # No se filtra por date_range a propósito — una señal abierta es "ahora", no un dato histórico
  # del rango seleccionado (ver riesgo del plan de Fase 5, documentado también en la UI).
  def risk_signals_summary
    open_signals = account.revenue_risk_signals.open

    {
      open: open_signals.order(detected_at: :desc).map { |signal| serialize_signal(signal) },
      by_category: open_signals.group(:category).count
    }
  end

  def serialize_signal(signal)
    signal.slice('id', 'category', 'signal_type', 'subject_type', 'subject_id', 'severity', 'first_detected_at', 'detected_at', 'context')
  end

  # Ancla a lead_created_at (cohorte: "de los leads que entraron en el periodo, ¿cómo les fue?"),
  # NO a la fecha del cierre — pregunta deliberadamente distinta a funnel_totals (que ancla a la
  # fecha del evento). Por eso `won`/`lost`/`open` de aquí pueden diferir del `closed_won` de
  # funnel_totals para el mismo periodo (un lead viejo que cerró esta semana cuenta en
  # funnel_totals pero no aquí si su fecha de creación quedó fuera del rango, y viceversa) —
  # INCIDENTE 2026-09-02: esto se reportó como "contradicción" en la UI. La UI ya NO muestra
  # won/lost/open de aquí como KPI destacado (ver Overview) para evitar la confusión; se
  # conservan en el payload solo para el desglose de tiempos promedio, que no tiene esa ambigüedad.
  def journeys_summary
    journeys = account.revenue_lead_journeys.where(lead_created_at: date_range)

    {
      total: journeys.count,
      won: journeys.won.count,
      lost: journeys.lost.count,
      open: journeys.where(won: false, lost: false).count,
      avg_time_to_first_response_seconds: avg_journey_metric(journeys, :time_to_first_response_seconds),
      avg_time_to_qualification_seconds: avg_journey_metric(journeys, :time_to_qualification_seconds),
      avg_time_to_appointment_seconds: avg_journey_metric(journeys, :time_to_appointment_seconds),
      avg_time_to_close_seconds: avg_journey_metric(journeys, :time_to_close_seconds)
    }
  end

  # AVG de Postgres ya ignora nulls (journeys sin ese hito) — no contarlos como 0 es la semántica
  # correcta (ver plan de Fase 5).
  def avg_journey_metric(journeys, column)
    average = journeys.average(column)
    average&.round
  end

  # Serie diaria (no por dimension_id) para la gráfica de evolución del Overview — mismo espíritu
  # que CallAnalysisAgentBuilder#score_evolution.
  def daily_trend(metrics)
    rollups_scope('funnel').where(metric: metrics).group(:date, :metric).sum(:count)
                           .each_with_object({}) do |((date, metric), count), acc|
      acc[date.to_s] ||= Hash.new(0)
      acc[date.to_s][metric] += count
    end
  end

  # Mismo número de días que date_range, inmediatamente anterior — para el badge de variación
  # (↑/↓ %) de cada KPI del Overview. Ninguna otra sección del payload usa este rango: el resto
  # sigue anclado a date_range únicamente.
  def previous_date_range
    days = (date_range.end - date_range.begin).to_i + 1
    (date_range.begin - days)..(date_range.begin - 1)
  end

  # { stage => { count:, previous_count:, delta_pct: } } para TODAS las etapas de
  # RefreshAggregatesJob::FUNNEL_EVENT_TYPES — no solo FUNNEL_SEQUENCE, incluye también
  # 'deal_created'/'closed_lost' para que la UI pueda mostrarlas como KPIs sueltos sin necesitar
  # una llamada aparte. IMPORTANTE (ver incidente 2026-09-02): esta es la ÚNICA fuente de verdad
  # para "cuántos X hubo en el periodo" en toda la pantalla — ancla siempre a la fecha del EVENTO
  # (cuándo pasó), nunca a la fecha de creación del lead. `journeys_summary` usa un ancla distinta
  # (cuándo se creó el lead) a propósito para una pregunta distinta (ver su comentario) — nunca
  # mostrar ambos como si fueran el mismo número en la UI.
  def funnel_totals
    current = stage_counts(date_range)
    previous = stage_counts(previous_date_range)

    RevenueIntelligence::RefreshAggregatesJob::FUNNEL_EVENT_TYPES.index_with do |stage|
      count = current[stage] || 0
      { count: count, previous_count: previous[stage] || 0, delta_pct: delta_pct(count, previous[stage] || 0) }
    end
  end

  def stage_counts(date_range_value)
    account.revenue_rollups.where(dimension_type: 'funnel', metric: RevenueIntelligence::RefreshAggregatesJob::FUNNEL_EVENT_TYPES,
                                  date: date_range_value)
           .group(:metric).sum(:count)
  end

  def delta_pct(count, previous_count)
    return nil if previous_count.zero?

    ((count - previous_count).to_f / previous_count * 100).round(1)
  end

  # { to_stage => rate } — conversión de la etapa anterior a esta, en el orden real de
  # FUNNEL_SEQUENCE (ej. 'lead_contacted' => contactados/leads).
  def funnel_conversions(totals)
    FUNNEL_SEQUENCE.each_cons(2).to_h do |from_stage, to_stage|
      [to_stage, safe_rate(totals[to_stage][:count], totals[from_stage][:count])]
    end
  end

  # Lista de hallazgos accionables — SOLO a partir de datos ya agregados, nunca cálculos nuevos
  # pesados en caliente (ver principio "la UI no hace joins costosos"). Cada insight es
  # {type:, direction:, params:} — el texto final (con números interpolados) se arma en el
  # frontend vía i18n, este builder nunca genera lenguaje natural directamente (mismo principio de
  # separación que el resto del payload).
  def insights
    [cta_insight, intent_level_insight, objection_insight, response_time_insight, risk_insight].compact
  end

  def cta_insight
    data = conversion_summary('call_conversion')
    used = data['cta_used:true']
    not_used = data['cta_used:false']
    return nil unless used && not_used && used['total'].positive? && not_used['total'].positive?

    { type: 'cta_conversion', direction: used['rate'] >= not_used['rate'] ? 'up' : 'down',
      params: { used_rate: pct(used['rate']), not_used_rate: pct(not_used['rate']) } }
  end

  # Reporta el segmento de intent_level con mayor conversión a cita — requiere al menos 3 llamadas
  # en ese segmento para no destacar un segmento con una sola llamada como si fuera una tendencia.
  def intent_level_insight
    data = conversion_summary('call_conversion')
    segments = data.select { |dimension_id, row| dimension_id.start_with?('intent_level:') && row['total'] >= 3 }
    return nil if segments.empty?

    dimension_id, row = segments.max_by { |_id, seg| seg['rate'] }
    { type: 'intent_level_conversion', direction: 'up', params: { level: dimension_id.split(':').last, rate: pct(row['rate']) } }
  end

  # Reporta la objeción con la conversión MÁS BAJA (solo si hay más de una para comparar, y
  # suficiente volumen) — evita alarmar sobre una objeción con 1-2 casos.
  def objection_insight
    data = conversion_summary('objection_conversion').select { |_id, row| row['total'] >= 3 }
    return nil if data.size < 2

    overall_rate = safe_rate(data.sum { |_id, row| row['converted'] }, data.sum { |_id, row| row['total'] })
    category, row = data.min_by { |_id, seg| seg['rate'] }
    return nil if row['rate'] >= overall_rate

    { type: 'worst_objection', direction: 'down',
      params: { category: category, rate: pct(row['rate']), diff_points: ((overall_rate - row['rate']) * 100).round(1) } }
  end

  # Compara la tasa de "llegó a cita" entre leads respondidos en <15 min vs. el resto — cohorte
  # por lead_created_at (igual que journeys_summary), no por evento; ver su comentario sobre por
  # qué esa ancla es la correcta para este tipo de pregunta.
  def response_time_insight
    journeys = account.revenue_lead_journeys.where(lead_created_at: date_range).where.not(time_to_first_response_seconds: nil)
    fast, slow = journeys.partition { |journey| journey.time_to_first_response_seconds <= 15.minutes.to_i }
    return nil if fast.size < 3 || slow.size < 3

    fast_rate = appointment_rate(fast)
    slow_rate = appointment_rate(slow)

    { type: 'response_time_conversion', direction: fast_rate >= slow_rate ? 'up' : 'down',
      params: { fast_rate: pct(fast_rate), slow_rate: pct(slow_rate) } }
  end

  def appointment_rate(journeys)
    return 0.0 if journeys.empty?

    journeys.count { |journey| journey.appointment_at.present? }.to_f / journeys.size
  end

  def risk_insight
    count = account.revenue_risk_signals.open.where(category: 'risk', signal_type: 'lead_no_contact').count
    return nil if count.zero?

    { type: 'leads_no_contact', direction: 'warning', params: { count: count } }
  end

  def pct(rate)
    (rate * 100).round(1)
  end
end
