# Calcula una pista de rol determinística (no la decisión final — eso lo hace el LLM, ver
# StructuredAnalysisLlmService) aplicando la regla de negocio "setter hasta que la cita
# efectivamente sucede, asesor desde que ya se realizó" — no es interpretación de texto, es un
# hecho de calendario. Se basa en si el contacto ya tiene un CallAnalysis previo cuya cita
# (outcome_type: "cita") ya haya pasado antes de esta llamada. Si no hay ningún antecedente claro,
# no fuerza nada — nil deja que el LLM decida solo con el contenido de la llamada.
class CallAnalysis::RoleHintResolver
  def initialize(call:)
    @call = call
  end

  def resolve
    return nil if previous_completed_appointment.blank?

    'asesor'
  end

  private

  attr_reader :call

  def previous_completed_appointment
    CallAnalysis.joins(:call)
                .where(account_id: call.account_id, calls: { contact_id: call.contact_id })
                .where(outcome_type: 'cita')
                .where('call_analyses.outcome_at <= ?', call.started_at || Time.current)
                .where.not(id: call.call_analysis&.id)
                .exists?
  end
end
