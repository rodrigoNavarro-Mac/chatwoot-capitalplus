# Calcula el score total ponderado a partir de los sub-scores por etapa que devuelve el LLM (ver
# CallAnalysis::StructuredAnalysisLlmService) — el LLM nunca calcula el total, así que cambiar
# pesos/umbrales (config/call_scorecards.yml) solo requiere volver a correr esta clase, no
# re-llamar al modelo (ver CallAnalysis::RescoreService).
class CallAnalysis::ScorecardCalculator
  def initialize(role:, stage_scores:)
    @role = role.to_s
    @stage_scores = stage_scores.symbolize_keys
    @weights = CallAnalysis::ScorecardConfig.weights(role)
    @thresholds = CallAnalysis::ScorecardConfig.thresholds(role)
  end

  # { stage_scores:, weights_used:, total_score:, reading: }
  def calculate
    return empty_result if weights.blank?

    total = weights.sum { |stage, weight| stage_scores.fetch(stage, 0).to_f * weight }

    {
      stage_scores: stage_scores,
      weights_used: weights,
      total_score: total.round(1),
      reading: reading_for(total)
    }
  end

  private

  attr_reader :role, :stage_scores, :weights, :thresholds

  def empty_result
    { stage_scores: stage_scores, weights_used: {}, total_score: nil, reading: nil }
  end

  def reading_for(total)
    return 'solido' if total >= thresholds.fetch(:solido, 80)
    return 'coaching' if total >= thresholds.fetch(:coaching, 60)

    'critico'
  end
end
