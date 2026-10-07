# Desglose completo de llamadas analizadas para exportar a CSV -- misma necesidad de auditoría
# que ya resolvió V2::Reports::RevenueIntelligenceLeadsExportBuilder para leads: cuando un número
# agregado del dashboard de Call Intelligence (ej. "cuántas llamadas con intent alta") se cuestiona,
# esto da la lista fila por fila para verificar contra Aircall/Zoho. Una fila por llamada
# ANALIZADA (completed_scope, mismo criterio que V2::Reports::CallAnalysisProjectBuilder) --
# llamadas sin análisis completo (pending/failed) no tienen objeciones/riesgos/outcome que exportar.
class V2::Reports::CallIntelligenceExportBuilder
  include DateRangeHelper

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    # :agent es asociación de CallAnalysis, :contact es asociación de Call -- no se puede anidar
    # ambos bajo `call:` (ahi solo caben asociaciones DE Call).
    scope.includes(:agent, call: :contact).find_each(batch_size: 200).map { |analysis| analysis_row(analysis) }
  end

  private

  attr_reader :account, :params

  DIRECT_FILTERS = %i[inbox_id agent_id confidence conversation_type].freeze

  def scope
    result = DIRECT_FILTERS.reduce(account.call_analyses.completed_scope) do |scope_so_far, key|
      params[key].present? ? scope_so_far.where(key => params[key]) : scope_so_far
    end
    range ? result.where(analyzed_at: range) : result
  end

  def analysis_row(analysis)
    call_attrs(analysis.call).merge(analysis_attrs(analysis))
  end

  def call_attrs(call)
    {
      call_id: call.id,
      provider_call_id: call.provider_call_id,
      contact_name: call.contact&.name,
      contact_phone: call.contact&.phone_number,
      started_at: call.started_at,
      duration_seconds: call.duration_seconds
    }
  end

  def analysis_attrs(analysis)
    {
      agent: analysis.agent&.name,
      role: analysis.role,
      conversation_type: analysis.conversation_type,
      intent_level: analysis.intent_level,
      confidence: analysis.confidence,
      outcome_type: analysis.outcome_type,
      outcome_at: analysis.outcome_at,
      top_objection: top_item(analysis.objections, 'category'),
      top_risk: top_item(analysis.risks, 'type'),
      zoho_deal_stage: analysis.zoho_deal_stage,
      analyzed_at: analysis.analyzed_at
    }
  end

  # La primera objeción/riesgo que el LLM reportó para esta llamada -- mismo criterio que
  # V2::Reports::CallAnalysisProjectBuilder#loss_reasons (el array ya viene ordenado por
  # relevancia desde CallAnalysis::StructuredAnalysisLlmService, no se reordena aquí).
  def top_item(items, key)
    Array(items).first&.dig(key)
  end
end
