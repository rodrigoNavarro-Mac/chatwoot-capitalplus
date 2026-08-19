# Genera un WeeklyOpsReport puntual pedido desde el dashboard (botón "Generar reporte"),
# en segundo plano — separado de Reports::GenerateWeeklyOpsReportJob (el cron semanal) porque este
# recibe el registro ya creado en estado "pending" y los parámetros de fecha exactos que mandó el
# usuario, en vez de calcular "la semana pasada" para cada inbox elegible.
#
# Corre en background porque V2::Reports::WeeklyOpsReportBuilder + Reports::WeeklyOpsAnalysisLlmService
# (que ahora pide al LLM el análisis ejecutivo Y el mini-análisis de las 15 cards en una sola
# llamada) puede tardar más de los 15s del timeout de Rack::Timeout en producción — confirmado en
# vivo 2026-08-18 (Rack::Timeout::RequestTimeoutException). El controller ya deja el registro en
# "pending" antes de encolar; este job lo deja en "completed" o "failed".
class Reports::GenerateOnDemandWeeklyOpsReportJob < ApplicationJob
  queue_as :high

  def perform(weekly_ops_report_id, report_params)
    record = WeeklyOpsReport.find_by(id: weekly_ops_report_id)
    return if record.blank?

    kpis = V2::Reports::WeeklyOpsReportBuilder.new(
      account: record.account, inbox: record.inbox, params: report_params.symbolize_keys
    ).build
    analysis = Reports::WeeklyOpsAnalysisLlmService.new(account: record.account, kpis: kpis).generate

    record.update!(
      kpis: kpis, llm_analysis: analysis[:executive_summary], card_analyses: analysis[:card_analyses], status: 'completed'
    )
  rescue StandardError => e
    record&.update_column(:status, 'failed') # rubocop:disable Rails/SkipsModelValidations -- solo cambia el status, sin validar kpis/period de nuevo
    ChatwootExceptionTracker.new(e, account: record&.account).capture_exception
  end
end
