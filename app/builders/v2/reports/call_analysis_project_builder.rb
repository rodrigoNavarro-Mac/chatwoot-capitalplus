# Reporte agregado de análisis de llamadas por proyecto/inbox — objeciones dominantes, motivos de
# pérdida, y desfase entre la etapa registrada en Zoho (snapshot al momento del análisis) y el
# resultado real de la conversación. v1 sin resumen ejecutivo LLM sobre estos agregados (fast
# follow si el volumen lo justifica, ver Fase 9 del plan) — agregación Ruby pura, igual de barata
# que el resto de los builders de v2/reports.
class V2::Reports::CallAnalysisProjectBuilder
  include DateRangeHelper

  attr_reader :account, :inbox, :params

  def initialize(account:, inbox:, params:)
    @account = account
    @inbox = inbox
    @params = params
  end

  def build
    {
      calls_analyzed: scope.count,
      objections_dominant: tally(:objections, 'category'),
      risks_recurrent: tally(:risks, 'type'),
      loss_reasons: loss_reasons,
      crm_vs_conversation_mismatch: crm_vs_conversation_mismatch
    }
  end

  private

  def scope
    scope = account.call_analyses.completed_scope.where(inbox_id: inbox.id)
    scope = scope.where(analyzed_at: range) if range
    scope
  end

  def tally(column, key)
    counts = Hash.new(0)
    scope.pluck(column).each do |items|
      Array(items).each { |item| counts[item[key]] += 1 if item.is_a?(Hash) && item[key].present? }
    end
    counts.sort_by { |_, count| -count }.first(10).to_h
  end

  # "sin_avance" con su objeción principal asociada — mejor proxy disponible sin una segunda
  # llamada LLM de síntesis (ver comentario de clase).
  def loss_reasons
    lost = scope.where(outcome_type: 'sin_avance')
    counts = Hash.new(0)
    lost.pluck(:objections).each do |objections|
      top = Array(objections).first
      counts[top&.dig('category') || 'sin_objecion_registrada'] += 1
    end
    { total_sin_avance: lost.count, by_top_objection: counts.sort_by { |_, c| -c }.to_h }
  end

  # Compara la etapa de Zoho al momento del análisis (snapshot en zoho_deal_stage) contra el
  # resultado real de la llamada — una llamada con outcome_type "cita" pero cuyo deal seguía en
  # una etapa temprana en Zoho sugiere que el CRM no se actualiza al mismo ritmo que la
  # conversación real (ver spec: "diferencias entre lo registrado en CRM y lo conversado").
  def crm_vs_conversation_mismatch
    scope.where.not(zoho_deal_stage: nil).where(outcome_type: 'cita')
         .group(:zoho_deal_stage).count
  end
end
