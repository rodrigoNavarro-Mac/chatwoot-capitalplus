# Orquesta el análisis estructurado de una llamada ya transcrita: valida precondiciones, calcula
# métricas determinísticas, llama al LLM, persiste y dispara la nota de Zoho. Idempotente por
# `call_id` (find_or_create_by!) — un reintento (manual o del cron, ver RetryFailedAnalysesJob)
# siempre actualiza la MISMA fila, nunca duplica transcripción ni análisis.
#
# Sin tabla de excepciones nueva a propósito — status/error_step/error_message/attempts en la
# propia fila + ChatwootExceptionTracker es el patrón real que ya usa este fork (ver
# Reports::GenerateOnDemandWeeklyOpsReportJob) para "excepción visible con contexto suficiente".
class CallAnalysis::AnalyzeJob < ApplicationJob
  queue_as :low

  def perform(call_id)
    call = Call.find_by(id: call_id)
    return if call.blank?

    record = find_or_create_record(call)
    return if record.completed?

    record.update!(status: 'processing', attempts: record.attempts + 1, last_attempted_at: Time.current)

    return if fail_unless_ready!(record, call)

    analyze!(record, call)
  rescue StandardError => e
    record&.update_columns(status: 'failed', error_message: e.message) # rubocop:disable Rails/SkipsModelValidations -- solo status/error, sin re-validar el resto
    ChatwootExceptionTracker.new(e, account: call&.account).capture_exception
  end

  private

  def find_or_create_record(call)
    CallAnalysis.find_or_create_by!(call_id: call.id) do |record|
      record.account_id = call.account_id
      record.inbox_id = call.inbox_id
      record.agent_id = call.accepted_by_agent_id
      record.provider_call_id = call.provider_call_id
    end
  end

  # Devuelve true (y ya dejó el registro en failed) si alguna precondición mínima no se cumple —
  # ver la lista de errores mínimos del spec: grabación no disponible, transcripción fallida,
  # usuario no identificado.
  def fail_unless_ready!(record, call)
    return fail_with!(record, 'recording_missing') unless call.recording.attached?
    return fail_with!(record, 'transcript_unavailable') if call.transcript_segments.blank?
    return fail_with!(record, 'agent_unidentified') if call.accepted_by_agent.blank?

    false
  end

  def fail_with!(record, step)
    record.update!(status: 'failed', error_step: step, error_message: step.to_s.humanize)
    true
  end

  def analyze!(record, call)
    agent_labels = agent_speaker_labels(call)
    metrics = Voice::ConversationMetricsCalculator.new(segments: call.transcript_segments, agent_speaker_labels: agent_labels).calculate
    role_hint = CallAnalysis::RoleHintResolver.new(call: call).resolve

    service = CallAnalysis::StructuredAnalysisLlmService.new(
      account: call.account, call: call, project_name: call.inbox.name, role_hint: role_hint, metrics: metrics
    )
    result = service.generate

    return fail_with!(record, result[:error]) if result[:error]

    persist_result!(record, metrics, result, service.model)
  end

  # El nombre del agente tal como aparece en la diarización de Aircall AI ("Agente principal:
  # Eunice Vazquez" en el ejemplo real de exportación) — se compara por nombre disponible del
  # usuario de Chatwoot en vez de un id, porque Aircall AI no expone un identificador interno
  # estable por hablante en su respuesta pública.
  def agent_speaker_labels(call)
    [call.accepted_by_agent&.name, call.accepted_by_agent&.available_name].compact.uniq
  end

  def persist_result!(record, metrics, result, llm_model)
    record.update!(classification_attributes(result).merge(extraction_attributes(metrics, result, llm_model)))

    CallAnalysis::PublishZohoNoteJob.perform_later(record.id) if record.should_publish_zoho_note?
  end

  def classification_attributes(result)
    {
      status: 'completed',
      analyzed_at: Time.current,
      role: result['role'],
      conversation_type: result['conversation_type'],
      confidence: result['confidence'],
      outcome_type: result['outcome_type'],
      outcome_at: parse_outcome_at(result['outcome_at']),
      intent_level: result['intent_level'],
      error_step: (result['confidence'] == 'low' ? 'low_confidence' : nil)
    }
  end

  def extraction_attributes(metrics, result, llm_model)
    {
      qualification_map: result['qualification_map'] || {},
      objections: result['objections'] || [],
      risks: result['risks'] || [],
      evidence: evidence(result),
      metrics: metrics,
      scorecard: CallAnalysis::ScorecardCalculator.new(role: result['role'], stage_scores: stage_scores(result)).calculate,
      llm_raw_response: result,
      llm_model: llm_model,
      prompt_version: CallAnalysis::StructuredAnalysisLlmService::PROMPT_VERSION,
      scorecard_config_version: CallAnalysis::ScorecardConfig::VERSION
    }
  end

  def stage_scores(result)
    (result['scorecard_stages'] || {}).transform_values { |v| v.is_a?(Hash) ? v['score'] : v }.symbolize_keys
  end

  def evidence(result)
    {
      'role_confidence_note' => result['role_confidence_note'],
      'intent_signals' => result['intent_signals'],
      'outcome_evidence' => result['outcome_evidence'],
      'contactability' => result['contactability'],
      'presentation_quality' => result['presentation_quality']
    }.compact
  end

  def parse_outcome_at(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
