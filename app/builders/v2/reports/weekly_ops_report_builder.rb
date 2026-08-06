# Arma los KPIs del "reporte semanal operativo" para UN inbox (= un desarrollo) y un rango de
# fechas: volumen, tiempos de contacto (reusando los rollups nativos de Chatwoot), pipeline/
# conversión de Zoho (reusando V2::Reports::SalesFunnelBuilder), desempeño de cadencias y de
# campañas masivas, y el comparativo contra el periodo inmediato anterior (misma duración).
#
# Tiempos de contacto: se leen de ReportingEventsRollup (dimension_type: 'inbox'), que Chatwoot ya
# calcula nativamente a partir de ReportingEvent:
#   - "first_response": tiempo hasta la primera respuesta del agente a un cliente en la
#     conversación (mapea a "Tiempo hasta primer mensaje de asesor").
#   - "reply_time": tiempo de respuesta promedio del agente a lo largo de la conversación (mapea a
#     "Tiempo de respuesta inicial").
class V2::Reports::WeeklyOpsReportBuilder
  include DateRangeHelper

  CONTACT_TIME_METRICS = %w[first_response reply_time].freeze

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
      pipeline: pipeline_metrics,
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

  def average_minutes_for(metric)
    rollups = ReportingEventsRollup.for_dimension('inbox', inbox.id).for_metric(metric)
    rollups = rollups.for_date_range(*date_bounds) if range.present?

    count = rollups.sum(:count)
    return nil if count.zero?

    (rollups.sum(:sum_value) / count / 60.0).round(2)
  end

  def pipeline_metrics
    V2::Reports::SalesFunnelBuilder.new(account: account, params: params.merge(inbox_ids: [inbox.id])).build.first
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
