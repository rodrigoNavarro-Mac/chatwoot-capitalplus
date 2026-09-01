# Reporte agregado de análisis de llamadas por agente/periodo — score promedio, distribución por
# tipo/rol, objeciones y riesgos recurrentes, evolución semanal del score (para ver efecto de
# coaching). Agregación pura en Ruby sobre CallAnalysis.completed — sin una segunda llamada LLM de
# roll-up (ver comentario de Fase 9 del plan: se deja como fast-follow si el volumen lo justifica).
class V2::Reports::CallAnalysisAgentBuilder
  include DateRangeHelper

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    {
      agents: agent_rows,
      objections_tally: tally(:objections, 'category'),
      risks_tally: tally(:risks, 'type'),
      score_evolution: score_evolution,
      conversation_type_tally: simple_tally(:conversation_type),
      confidence_tally: simple_tally(:confidence),
      score_reading_tally: score_reading_tally
    }
  end

  private

  def scope
    scope = account.call_analyses.completed_scope.includes(:call)
    scope = scope.where(agent_id: params[:agent_id]) if params[:agent_id].present?
    scope = scope.where(confidence: params[:confidence]) if params[:confidence].present?
    scope = scope.where(conversation_type: params[:conversation_type]) if params[:conversation_type].present?
    scope = scope.where(analyzed_at: range) if range
    scope
  end

  def agent_rows
    scope.includes(:agent).group_by(&:agent_id).filter_map do |agent_id, records|
      next if agent_id.blank?

      agent_row(agent_id, records)
    end
  end

  # `calls_analyzed` cuenta TODO lo analizado (incluye buzón — es contactabilidad real), pero
  # `average_score` y `score_evolution` solo tienen sentido sobre conversaciones reales: un buzón
  # de voz tiene un scorecard casi en 0 por falta de conversación, no por mala calidad del agente —
  # mezclarlo hundía el promedio sin decir nada útil (CONFIRMADO 2026-09-01: 17.4/100 de promedio
  # con 517 llamadas de una agente, la mayoría buzón). Mismo criterio que
  # V2::Reports::SalesFunnelBuilder#answered_call_conversation_ids y
  # V2::Reports::WeeklyOpsReportCallsMetrics#voicemail_metrics.
  def agent_row(agent_id, records)
    real_conversations = records.reject(&:low_confidence?)
    voicemail_count = records.size - real_conversations.size

    {
      agent_id: agent_id,
      agent_name: records.first.agent&.available_name,
      calls_analyzed: records.size,
      voicemail_count: voicemail_count,
      voicemail_percent: safe_rate(voicemail_count, records.size),
      average_score: average(real_conversations),
      conversation_type_distribution: records.group_by(&:conversation_type).transform_values(&:size),
      role_distribution: records.group_by(&:role).transform_values(&:size)
    }
  end

  def average(records)
    scores = records.filter_map(&:total_score)
    return nil if scores.empty?

    (scores.sum.to_f / scores.size).round(1)
  end

  def safe_rate(numerator, denominator)
    return 0.0 if denominator.to_i.zero?

    (numerator.to_f / denominator * 100).round(2)
  end

  def tally(column, key)
    counts = Hash.new(0)
    scope.pluck(column).each do |items|
      Array(items).each { |item| counts[item[key]] += 1 if item.is_a?(Hash) && item[key].present? }
    end
    counts.sort_by { |_, count| -count }.first(10).to_h
  end

  # Distribución global (todos los agentes, todo el periodo filtrado) — a diferencia de
  # `conversation_type_distribution` en #agent_row, que es por agente. Sirve para las gráficas de
  # "cantidad por tipo" / "confianza" a nivel cuenta que pidió el cliente.
  def simple_tally(column)
    scope.group(column).count.compact_blank
  end

  # Buzón de voz (confidence: low) no tiene lectura real de scorecard — se excluye, mismo criterio
  # que #average_score.
  def score_reading_tally
    scope.reject(&:low_confidence?).filter_map(&:score_reading).tally
  end

  # Agrupa por la semana en que ocurrió la llamada (call.started_at), no en la que se analizó
  # (analyzed_at) — un backfill histórico analiza semanas de llamadas viejas en un solo día, y
  # agrupar por analyzed_at colapsaba meses de evolución real en un único punto (CONFIRMADO
  # 2026-09-01). Solo conversaciones reales, mismo criterio que #agent_row.
  def score_evolution
    scope.reject(&:low_confidence?).select { |record| record.call.started_at.present? }
         .group_by { |record| record.call.started_at.to_date.beginning_of_week }
         .transform_values { |records| average(records) }
         .sort.to_h
  end
end
