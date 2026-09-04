# Abre/toca/cierra filas de RevenueRiskSignal para un (account, category) dado — compartido por
# RevenueIntelligence::DetectRisksJob y DetectDataQualityIssuesJob para no duplicar el patrón
# "abrir si la condición aplica, resolver las que ya no aplican" en ambos jobs. A diferencia del
# resto de Revenue Intelligence, estos jobs no usan RevenueIntelligence::SyncCursorService: cada
# corrida reevalúa el universo COMPLETO de candidatos de cada signal_type (ver riesgos de Fase 4
# sobre por qué esto es aceptable al volumen actual).
class RevenueIntelligence::RiskSignalRecorder
  def initialize(account, category:)
    @account = account
    @category = category
  end

  # Abre una señal nueva o toca (detected_at/severity/context) la que ya estaba abierta para este
  # sujeto — nunca duplica gracias al índice único parcial (where resolved_at IS NULL).
  def record(signal_type:, subject_type:, subject_id:, severity: 'medium', context: {})
    now = Time.current
    signal = @account.revenue_risk_signals.find_or_initialize_by(category: @category, signal_type: signal_type,
                                                                 subject_type: subject_type, subject_id: subject_id, resolved_at: nil)
    signal.first_detected_at ||= now
    signal.detected_at = now
    signal.severity = severity
    signal.context = context
    signal.save!
  end

  # Cierra toda señal ABIERTA de este signal_type cuyo subject_id ya no esté entre los candidatos
  # detectados en la corrida actual — así una señal se resuelve sola sin que el job tenga que saber
  # "antes esto estaba mal, ahora ya no".
  def resolve_stale!(signal_type:, active_subject_ids:)
    @account.revenue_risk_signals.open.where(category: @category, signal_type: signal_type)
            .where.not(subject_id: active_subject_ids)
            .update_all(resolved_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
