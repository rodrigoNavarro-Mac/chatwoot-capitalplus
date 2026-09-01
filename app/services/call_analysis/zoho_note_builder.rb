# Arma el resumen corto que se escribe como Nota en Zoho — NUNCA el JSON completo del análisis
# ("sin saturar la ficha", spec del cliente). El detalle completo (mapa de calificación, objeciones
# con cita textual, riesgos, evidencia) vive solo en Chatwoot (call_analyses), consultable por
# conversación/persona/proyecto — ver Fase 9 del plan.
class CallAnalysis::ZohoNoteBuilder
  OBJECTIONS_LIMIT = 3

  def initialize(call_analysis)
    @analysis = call_analysis
    @call = call_analysis.call
  end

  def title
    "Análisis de llamada — #{analysis.role}/#{analysis.conversation_type} — #{call.started_at&.to_date}"
  end

  def content
    [
      confidence_caveat_line,
      header_line,
      outcome_line,
      intent_and_score_line,
      objections_line,
      next_step_line,
      risks_line,
      conversation_link_line
    ].compact.join("\n")
  end

  private

  attr_reader :analysis, :call

  # Un buzón de voz o llamada sin respuesta también cuenta como contactabilidad, pero no es un
  # análisis de conversación real — esta línea deja claro que el resto de la nota (rol, score,
  # etc.) es de baja certeza en vez de mezclarla sin aviso con análisis de conversaciones reales.
  def confidence_caveat_line
    return nil unless analysis.low_confidence?

    '⚠️ Confianza baja — probable buzón de voz o llamada sin interacción real, no un análisis completo de conversación.'
  end

  def header_line
    "Llamada #{analysis.role} · #{analysis.conversation_type} · #{call.started_at&.strftime('%d/%m/%Y %H:%M')} " \
      "· #{call.duration_seconds.to_i / 60} min"
  end

  def outcome_line
    date = analysis.outcome_at.present? ? " (#{analysis.outcome_at.strftime('%d/%m/%Y')})" : ''
    "Resultado: #{analysis.outcome_type}#{date}"
  end

  def intent_and_score_line
    "Intención: #{analysis.intent_level}   Score: #{analysis.total_score}/100 (#{analysis.score_reading})"
  end

  def objections_line
    categories = Array(analysis.objections).first(OBJECTIONS_LIMIT).pluck('category')
    return nil if categories.blank?

    "Objeciones principales: #{categories.join(', ')}"
  end

  def next_step_line
    evidence = analysis.evidence.is_a?(Hash) ? analysis.evidence['outcome_evidence'] : nil
    return nil if evidence.blank?

    "Próximo paso: #{evidence}"
  end

  def risks_line
    types = Array(analysis.risks).pluck('type')
    return nil if types.blank?

    "Riesgos detectados: #{types.join(', ')}"
  end

  def conversation_link_line
    frontend_url = ENV['FRONTEND_URL'].presence
    return nil if frontend_url.blank?

    "Ver análisis completo en Chatwoot → #{frontend_url.chomp('/')}/app/accounts/#{call.account_id}/conversations/#{call.conversation.display_id}"
  end
end
