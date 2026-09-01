# Cola de revisión/errores del análisis de llamadas (ver CallAnalysis.needs_review) + botón
# "Reintentar" — reencola CallAnalysis::AnalyzeJob con la MISMA llave (call_id), nunca duplica.
# #show/#recent alimentan el modal de detalle de una llamada individual (mapa de calificación,
# objeciones con cita textual, scorecard por etapa) — usado tanto desde el reporte de Call
# Intelligence como desde la burbuja de la llamada en la conversación. #recent acepta los mismos
# filtros que V2::Reports::CallAnalysisAgentBuilder (agent_id/confidence/conversation_type/
# inbox_id/since/until) más paginación — para poder auditar TODO lo analizado, no solo un top 50
# fijo sin relación con lo que el usuario esté filtrando en el reporte.
class Api::V1::Accounts::CallAnalysesController < Api::V1::Accounts::BaseController
  include DateRangeHelper

  RESULTS_PER_PAGE = 25

  before_action :check_authorization
  before_action :fetch_call_analysis, only: [:show, :retry]

  def index
    @call_analyses = Current.account.call_analyses.needs_review.order(last_attempted_at: :desc).limit(50)
  end

  def show; end

  def recent
    @call_analyses = recent_scope.page(current_page).per(RESULTS_PER_PAGE)
    @total_count = recent_scope.count
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

  def recent_scope
    apply_filters(Current.account.call_analyses.completed_scope.includes(:agent)).order(analyzed_at: :desc)
  end

  def apply_filters(scope)
    scope = apply_id_filters(scope)
    scope = scope.where(confidence: params[:confidence]) if params[:confidence].present?
    scope = scope.where(conversation_type: params[:conversation_type]) if params[:conversation_type].present?
    scope = scope.where(analyzed_at: range) if range
    scope
  end

  def apply_id_filters(scope)
    scope = scope.where(agent_id: params[:agent_id]) if params[:agent_id].present?
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    scope
  end

  def current_page
    params[:page] || 1
  end
end
