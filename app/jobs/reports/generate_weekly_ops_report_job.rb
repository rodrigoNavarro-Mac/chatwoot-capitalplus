# Genera y guarda el WeeklyOpsReport de la semana recién cerrada (lunes-domingo anterior) para
# cada inbox con al menos una CadenceDefinition activa — esos son los inboxes que este fork usa
# como "desarrollo" operativo (ver CadenceDefinition, que ya vive scoped a inbox_id). No genera el
# PDF: eso se arma on-demand al descargar (Reports::WeeklyOpsReportPdfService), porque necesita las
# imágenes de las gráficas que renderiza el frontend.
class Reports::GenerateWeeklyOpsReportJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    eligible_inboxes.find_each do |inbox|
      generate_for(inbox)
    rescue StandardError => e
      Rails.logger.error "[Reports::GenerateWeeklyOpsReportJob] inbox=#{inbox.id} error=#{e.message}"
    end
  end

  private

  def eligible_inboxes
    Inbox.joins(:cadence_definitions).merge(CadenceDefinition.active).distinct
  end

  def generate_for(inbox)
    account = inbox.account
    since_date = local_zone(inbox).now.to_date.beginning_of_week(:monday) - 7.days
    until_date = since_date + 7.days

    kpis = V2::Reports::WeeklyOpsReportBuilder.new(
      account: account,
      inbox: inbox,
      params: { since: local_epoch(inbox, since_date).to_s, until: local_epoch(inbox, until_date).to_s, period_type: 'week' }
    ).build
    analysis = Reports::WeeklyOpsAnalysisLlmService.new(account: account, kpis: kpis).generate

    period = kpis[:period] || {}
    record = inbox.weekly_ops_reports.find_or_initialize_by(period_start: period[:since], period_type: 'week')
    record.update!(account: account, period_end: period[:until], kpis: kpis, llm_analysis: analysis[:executive_summary],
                   card_analyses: analysis[:card_analyses], status: 'completed')
  end

  # El rango de la semana (lunes-domingo) se calcula en la zona horaria del INBOX, no en la de Rails
  # (config.time_zone nunca se configuró — default UTC). Con UTC, el borde final de cada semana
  # (domingo medianoche local -> lunes ~06:00 UTC en México) recortaba conversaciones del propio
  # domingo del reporte, que en Zoho sí cuentan para esa semana — caso real detectado 2026-09-03:
  # el reporte semanal (24-30 agosto) mostraba 46 leads en Chatwoot vs 52 reales en Zoho, y 5 de los
  # 6 faltantes eran domingo 30 de agosto en hora de México, guardados como madrugada del 31 en UTC.
  def local_zone(inbox)
    ActiveSupport::TimeZone[inbox.timezone.presence || 'UTC']
  end

  def local_epoch(inbox, date)
    local_zone(inbox).local(date.year, date.month, date.day).to_i
  end
end
