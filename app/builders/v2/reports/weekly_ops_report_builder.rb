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
class V2::Reports::WeeklyOpsReportBuilder
  include DateRangeHelper

  CONTACT_TIME_METRICS = %w[first_response reply_time].freeze

  # Valores internos ("actual_value") del campo Lead_Status en Zoho de esta cuenta, confirmados
  # contra la API real (Api::CRM::getFields sobre el módulo Leads) — no son los labels en español
  # que se ven en la UI de Zoho (que están traducidos). Mismo criterio que
  # V2::Reports::SalesFunnelBuilder::VISITA_EFECTIVA_STAGES para el Stage de Deals.
  LEAD_STATUS_LABELS = {
    'Nuevo contacto' => 'Nuevo contacto',
    'Attempted to Contact' => 'Intento de contacto',
    'Contact in Future' => 'Contactar en el futuro',
    'Contacted' => 'Contactado',
    'Calificado' => 'Calificado',
    'Lost Lead' => 'Cliente perdido/Descartado',
    'Pre-Qualified' => 'Previamente clasificado',
    'Not Contacted' => 'Contacto no exitoso',
    'Not Qualified' => 'No habilitado',
    'Junk Lead' => 'Posible cliente no solicitado'
  }.freeze
  LOST_LEAD_STATUS = 'Lost Lead'.freeze
  CONTACTED_STATUS = 'Contacted'.freeze

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
      by_advisor: by_advisor_metrics,
      pipeline: pipeline_metrics,
      zoho_leads: zoho_leads_metrics,
      zoho_leads_timeline: leads_timeline_metrics,
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
    CONTACT_TIME_METRICS.to_h { |metric| [metric.to_sym, average_minutes_for(metric)] }
  end

  def average_minutes_for(metric, user_id: nil)
    events = reporting_events_for(metric, user_id: user_id)
    count = events.count
    return nil if count.zero?

    (events.sum(Arel.sql('COALESCE(value_in_business_hours, value)')) / count / 60.0).round(2)
  end

  def reporting_events_for(metric, user_id: nil)
    events = contact_time_events.where(name: metric)
    events = events.where(user_id: user_id) if user_id.present?
    events
  end

  def contact_time_events
    events = ReportingEvent.where(inbox_id: inbox.id, name: CONTACT_TIME_METRICS)
    events = events.where(created_at: range) if range.present?
    events
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

  def advisor_conversations_scope
    conversations = inbox.conversations
    conversations = conversations.where(created_at: range) if range.present?
    conversations
  end

  def advisor_stats(user_id)
    {
      user_id: user_id,
      name: advisor_name(user_id),
      conversations_count: advisor_conversations_scope.where(assignee_id: user_id).count,
      contact_time: CONTACT_TIME_METRICS.to_h { |metric| [metric.to_sym, average_minutes_for(metric, user_id: user_id)] }
    }
  end

  def advisor_name(user_id)
    User.find_by(id: user_id)&.name || "Agente #{user_id}"
  end

  def pipeline_metrics
    V2::Reports::SalesFunnelBuilder.new(account: account, params: params.merge(inbox_ids: [inbox.id])).build.first
  end

  # Distribución de leads de Zoho (estado, fuente, motivo de descarte) para este desarrollo y
  # periodo — consultado en vivo (ver Crm::Zoho::LeadsForPeriodService), a diferencia de
  # #pipeline_metrics que solo mira contactos que ya tienen conversación en Chatwoot. Si el inbox
  # no tiene "desarrollo" configurado, o Zoho no responde, no bloquea el resto del reporte: queda
  # en nil y el frontend/PDF/docx simplemente omiten la sección.
  def zoho_leads_metrics
    return nil if development_key.blank? || range.blank?

    leads = zoho_leads
    return nil if leads.blank?

    lost_leads = leads.select { |lead| lead['Lead_Status'] == LOST_LEAD_STATUS }
    quality_count = leads.count { |lead| lead['Lead_Status'] == CONTACTED_STATUS }

    {
      total: leads.size,
      by_status: count_by(leads, 'Lead_Status', LEAD_STATUS_LABELS),
      by_source: count_by(leads, 'Lead_Source'),
      discard_reasons: count_by(lost_leads, 'Raz_n_de_descarte'),
      quality_leads_count: quality_count,
      quality_leads_percent: safe_rate(quality_count, leads.size)
    }
  end

  def zoho_leads
    @zoho_leads ||= Crm::Zoho::LeadsForPeriodService.new(account: account, development_key: development_key, range: range).fetch
  end

  def leads_timeline_metrics
    return nil if development_key.blank? || range.blank?

    granularity = TIMELINE_GRANULARITY_BY_PERIOD_TYPE.fetch(params[:period_type], 'day')
    V2::Reports::LeadsTimelineMetrics.new(leads: zoho_leads, range: range, granularity: granularity, account: account).build
  end

  def development_key
    inbox.agent_bot&.bot_config&.dig('variables', 'desarrollo')
  end

  def count_by(leads, field, labels = nil)
    leads.filter_map { |lead| lead[field] }
         .tally
         .transform_keys { |value| labels ? labels.fetch(value, value) : value }
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
