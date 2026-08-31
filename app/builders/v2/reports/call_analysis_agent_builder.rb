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
      score_evolution: score_evolution
    }
  end

  private

  def scope
    scope = account.call_analyses.completed_scope
    scope = scope.where(agent_id: params[:agent_id]) if params[:agent_id].present?
    scope = scope.where(analyzed_at: range) if range
    scope
  end

  def agent_rows
    scope.includes(:agent).group_by(&:agent_id).filter_map do |agent_id, records|
      next if agent_id.blank?

      agent_row(agent_id, records)
    end
  end

  def agent_row(agent_id, records)
    {
      agent_id: agent_id,
      agent_name: records.first.agent&.available_name,
      calls_analyzed: records.size,
      average_score: average(records),
      conversation_type_distribution: records.group_by(&:conversation_type).transform_values(&:size),
      role_distribution: records.group_by(&:role).transform_values(&:size)
    }
  end

  def average(records)
    scores = records.filter_map(&:total_score)
    return nil if scores.empty?

    (scores.sum.to_f / scores.size).round(1)
  end

  def tally(column, key)
    counts = Hash.new(0)
    scope.pluck(column).each do |items|
      Array(items).each { |item| counts[item[key]] += 1 if item.is_a?(Hash) && item[key].present? }
    end
    counts.sort_by { |_, count| -count }.first(10).to_h
  end

  def score_evolution
    scope.where.not(analyzed_at: nil).group_by { |record| record.analyzed_at.to_date.beginning_of_week }
         .transform_values { |records| average(records) }
         .sort.to_h
  end
end
