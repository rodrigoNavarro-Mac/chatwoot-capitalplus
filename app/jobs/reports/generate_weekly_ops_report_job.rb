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
    since_date = Date.current.beginning_of_week(:monday) - 7.days
    until_date = since_date + 7.days

    kpis = V2::Reports::WeeklyOpsReportBuilder.new(
      account: account,
      inbox: inbox,
      params: { since: since_date.beginning_of_day.to_i.to_s, until: until_date.beginning_of_day.to_i.to_s }
    ).build
    analysis = Reports::WeeklyOpsAnalysisLlmService.new(account: account, kpis: kpis).generate

    period = kpis[:period] || {}
    record = inbox.weekly_ops_reports.find_or_initialize_by(period_start: period[:since])
    record.update!(account: account, period_end: period[:until], kpis: kpis, llm_analysis: analysis, status: 'completed')
  end
end
