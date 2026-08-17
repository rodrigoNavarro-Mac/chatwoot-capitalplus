# Arma los KPIs del "reporte semanal operativo" para UN inbox (= un desarrollo) y un rango de
# fechas: volumen, tiempos de contacto, desglose por asesor, pipeline/conversión de Zoho (reusando
# V2::Reports::SalesFunnelBuilder), desempeño de cadencias y de campañas masivas, y el comparativo
# contra el periodo inmediato anterior (misma duración).
#
# Tiempos de contacto: se leen directo de ReportingEvent (no del rollup ReportingEventsRollup) por
# dos razones: (1) el rollup solo se llena si Account#reporting_timezone está configurado, y
# depender de eso causó que los tiempos salieran vacíos en producción hasta configurarlo y
# correr un backfill; (2) el rollup no soporta la dimensión combinada agente+inbox, que sí
# necesitamos para el desglose por asesor. Para un reporte semanal de un solo inbox el volumen de
# eventos es chico, así que consultar en vivo no es un problema de performance.
#   - "first_response": tiempo hasta la primera respuesta del agente a un cliente en la
#     conversación (mapea a "Tiempo hasta primer mensaje de asesor").
#   - "reply_time": tiempo de respuesta promedio del agente a lo largo de la conversación (mapea a
#     "Tiempo de respuesta inicial").
#
# Ambas métricas usan `value_in_business_hours` (tiempo transcurrido contando solo minutos dentro
# del horario laboral configurado en el inbox — ver WorkingHour/ReportingEventListener), no el
# tiempo crudo, igual que el reporte semanal anterior en Python.
#
# Se reportan como MEDIANA, no promedio: el promedio se vio disparado por un puñado de
# conversaciones viejas (de semanas atrás) cuyo primer contacto ocurrió recién esta semana —
# probablemente por lotes de backfill (ver lib/tasks/backfill_first_reply.rake) que crean el
# ReportingEvent con created_at de hoy pero un gap real de semanas. Detectado 2026-08-17: 5 de los
# eventos de "Fuego" con mayor value_in_business_hours compartían event_end_time casi idéntico
# (11 segundos de diferencia entre sí) pero event_start_time de mediados de julio — la firma de un
# proceso por lotes, no de clientes respondiendo en el mismo segundo. La mediana es inmune a esos
# outliers; además se descartan explícitamente (ver MAX_CONTACT_GAP) para que tampoco distorsionen
# semanas con poco volumen donde hasta la mediana podría verse afectada.
class V2::Reports::WeeklyOpsReportBuilder
  include DateRangeHelper

  CONTACT_TIME_METRICS = %w[first_response reply_time].freeze

  # Un contacto con más de este gap (tiempo de reloj real, no horario laboral) casi seguro no
  # refleja el ritmo de atención de la semana del reporte — se descarta del cálculo.
  MAX_CONTACT_GAP = 7.days.freeze

  # Granularidad de la gráfica de leads por periodo, según el tipo de reporte — semana → día,
  # mes → semana, trimestre → mes (ver V2::Reports::LeadsTimelineMetrics).
  TIMELINE_GRANULARITY_BY_PERIOD_TYPE = { 'week' => 'day', 'month' => 'week', 'quarter' => 'month' }.freeze

  attr_reader :account, :inbox, :params

  def initialize(account:, inbox:, params:, include_comparison: true)
    @account = account
    @inbox = inbox
    @params = params
    @include_comparison = include_comparison
  end

  def build
    {
      inbox_id: inbox.id,
      inbox_name: inbox.name,
      period: period_payload,
      volume: volume_metrics,
      contact_time: contact_time_metrics,
      contact_time_by_period_of_week: contact_time_by_period_of_week,
      by_advisor: by_advisor_metrics,
      pipeline: pipeline_metrics,
      zoho_leads: zoho_leads_service.summary,
      zoho_leads_timeline: leads_timeline_metrics,
      deals_created: zoho_leads_service.deals_created,
      conversion_by_owner: zoho_leads_service.conversion_by_owner,
      schedule_distribution: zoho_leads_service.schedule_distribution,
      aircall_calls: aircall_calls_metrics,
      cadences: cadence_metrics,
      campaigns: campaign_metrics,
      comparison: include_comparison? ? comparison_metrics : nil
    }
  end

  private

  def include_comparison?
    @include_comparison
  end

  def period_payload
    return {} if range.blank?

    { since: date_bounds.first, until: date_bounds.last }
  end

  # Último día incluido en el rango (el rango es exclusivo por la derecha, ver DateRangeHelper).
  def date_bounds
    @date_bounds ||= [range.begin.to_date, (range.end - 1.second).to_date]
  end

  def volume_metrics
    conversations = inbox.conversations
    conversations = conversations.where(created_at: range) if range.present?

    { new_conversations: conversations.count }
  end

  def contact_time_metrics
    CONTACT_TIME_METRICS.to_h { |metric| [metric.to_sym, median_minutes_for(metric)] }
  end

  # Lun-Vie vs Sáb-Dom, igual que el reporte semanal anterior en Python — para detectar si el
  # tiempo de contacto se deteriora fuera de la operación entre semana.
  def contact_time_by_period_of_week
    {
      weekday: CONTACT_TIME_METRICS.to_h { |m| [m.to_sym, median_minutes_for(m, weekday: true)] },
      weekend: CONTACT_TIME_METRICS.to_h { |m| [m.to_sym, median_minutes_for(m, weekday: false)] }
    }
  end

  # Excluye eventos sin value_in_business_hours calculado en vez de caer al tiempo crudo (reloj
  # real 24/7) — un fallback silencioso a tiempo crudo infla la métrica muy por encima del
  # horario laboral real cuando el horario del inbox no cubre esos eventos.
  def median_minutes_for(metric, user_id: nil, weekday: nil)
    values = reporting_events_for(metric, user_id: user_id, weekday: weekday)
             .where.not(value_in_business_hours: nil)
             .where('value <= ?', MAX_CONTACT_GAP.to_i)
             .order(:value_in_business_hours)
             .pluck(:value_in_business_hours)
    return nil if values.empty?

    (median(values) / 60.0).round(2)
  end

  def median(values)
    count = values.size
    middle = count / 2
    count.odd? ? values[middle] : (values[middle - 1] + values[middle]) / 2.0
  end

  def reporting_events_for(metric, user_id: nil, weekday: nil)
    events = contact_time_events(weekday: weekday).where(name: metric)
    events = events.where(user_id: user_id) if user_id.present?
    events
  end

  def contact_time_events(weekday: nil)
    events = ReportingEvent.where(inbox_id: inbox.id, name: CONTACT_TIME_METRICS)
    events = events.where(created_at: range) if range.present?
    filter_by_weekday(events, weekday)
  end

  # weekday: true → lunes-viernes, false → sábado-domingo, nil → sin filtro.
  def filter_by_weekday(scope, weekday)
    return scope if weekday.nil?

    days = weekday ? (1..5).to_a : [0, 6]
    scope.where('EXTRACT(DOW FROM created_at) IN (?)', days)
  end

  def by_advisor_metrics
    relevant_agent_ids.map { |user_id| advisor_stats(user_id) }
                      .sort_by { |advisor| -advisor[:conversations_count] }
  end

  # Solo agentes con al menos una conversación asignada en el periodo — un agente que solo
  # respondió un mensaje puntual sin quedar asignado (o una cuenta de admin/prueba) no cuenta
  # como "asesor" para efectos de este desglose.
  def relevant_agent_ids
    advisor_conversations_scope.where.not(assignee_id: nil).distinct.pluck(:assignee_id)
  end

  def advisor_conversations_scope(weekday: nil)
    conversations = inbox.conversations
    conversations = conversations.where(created_at: range) if range.present?
    filter_by_weekday(conversations, weekday)
  end

  def advisor_stats(user_id)
    {
      user_id: user_id,
      name: advisor_name(user_id),
      conversations_count: advisor_conversations_scope.where(assignee_id: user_id).count,
      contact_time: CONTACT_TIME_METRICS.to_h { |metric| [metric.to_sym, median_minutes_for(metric, user_id: user_id)] },
      by_period_of_week: advisor_period_of_week_stats(user_id)
    }
  end

  def advisor_period_of_week_stats(user_id)
    [true, false].to_h do |weekday|
      key = weekday ? :weekday : :weekend
      [key, { conversations_count: advisor_conversations_scope(weekday: weekday).where(assignee_id: user_id).count,
              contact_time: CONTACT_TIME_METRICS.to_h { |m| [m.to_sym, median_minutes_for(m, user_id: user_id, weekday: weekday)] } }]
    end
  end

  def advisor_name(user_id)
    User.find_by(id: user_id)&.name || "Agente #{user_id}"
  end

  def pipeline_metrics
    V2::Reports::SalesFunnelBuilder.new(account: account, params: params.merge(inbox_ids: [inbox.id])).build.first
  end

  def zoho_leads_service
    @zoho_leads_service ||= V2::Reports::ZohoLeadsMetrics.new(account: account, development_key: development_key, range: range, inbox: inbox)
  end

  def leads_timeline_metrics
    return nil if development_key.blank? || range.blank?

    granularity = TIMELINE_GRANULARITY_BY_PERIOD_TYPE.fetch(params[:period_type], 'day')
    V2::Reports::LeadsTimelineMetrics.new(leads: zoho_leads_service.leads, range: range, granularity: granularity, account: account).build
  end

  def development_key
    inbox.agent_bot&.bot_config&.dig('variables', 'desarrollo')
  end

  # "aircall_calls" y no "calls" para no confundirse con cadences[:calls_completed]/[:calls_pending]
  # (tareas de llamada manual de cadencias, otra feature). Extraído a una clase aparte
  # (V2::Reports::WeeklyOpsReportCallsMetrics) solo para no pasar el límite de tamaño de esta clase.
  def aircall_calls_metrics
    V2::Reports::WeeklyOpsReportCallsMetrics.new(inbox: inbox, range: range).build
  end

  def cadence_metrics
    enrollments = CadenceEnrollment.where(inbox_id: inbox.id).filter_by_date_range(range)
    total = enrollments.count
    responded = enrollments.where.not(last_lead_response_at: nil).count
    call_tasks = CadenceCallTask.where(cadence_enrollment_id: enrollments.select(:id))

    {
      total_enrollments: total,
      responded: responded,
      response_rate: safe_rate(responded, total),
      by_status: enrollments.group(:status).count,
      calls_completed: call_tasks.completed.count,
      calls_pending: call_tasks.pending.count
    }
  end

  def campaign_metrics
    campaigns = Campaign.where(inbox_id: inbox.id)
    deliveries = CampaignMessageDelivery.where(campaign_id: campaigns.select(:id))
    deliveries = deliveries.where(created_at: range) if range.present?

    {
      campaigns_count: campaigns.count,
      messages_sent: deliveries.where.not(sent_at: nil).count,
      messages_delivered: deliveries.where.not(delivered_at: nil).count,
      messages_read: deliveries.where.not(read_at: nil).count,
      messages_responded: deliveries.where.not(responded_at: nil).count
    }
  end

  # Mismo builder, mismo tamaño de rango, desplazado hacia atrás — evita recursión pasando
  # include_comparison: false.
  def comparison_metrics
    return nil if range.blank?

    duration = range.end - range.begin
    prev_params = params.merge(
      since: (range.begin - duration).to_time.to_i.to_s,
      until: range.begin.to_time.to_i.to_s
    )

    self.class.new(account: account, inbox: inbox, params: prev_params, include_comparison: false).build
  end

  def safe_rate(numerator, denominator)
    return 0.0 if denominator.to_i.zero?

    (numerator.to_f / denominator * 100).round(2)
  end
end
