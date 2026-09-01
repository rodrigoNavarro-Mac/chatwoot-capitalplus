# Cola de revisión/errores del análisis de llamadas (ver CallAnalysis.needs_review) + botón
# "Reintentar" — reencola CallAnalysis::AnalyzeJob con la MISMA llave (call_id), nunca duplica.
# #show/#recent alimentan el modal de detalle de una llamada individual (mapa de calificación,
# objeciones con cita textual, scorecard por etapa) — usado tanto desde el reporte de Call
# Intelligence como desde la burbuja de la llamada en la conversación.
class Api::V1::Accounts::CallAnalysesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_call_analysis, only: [:show, :retry]

  def index
    @call_analyses = Current.account.call_analyses.needs_review.order(last_attempted_at: :desc).limit(50)
  end

  def show; end

  def recent
    @call_analyses = Current.account.call_analyses.completed_scope.includes(:agent).order(analyzed_at: :desc).limit(50)
  end

  def retry
    CallAnalysis::AnalyzeJob.perform_later(@call_analysis.call_id)
    head :ok
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  def fetch_call_analysis
    @call_analysis = Current.account.call_analyses.find(params[:id])
  end
end
