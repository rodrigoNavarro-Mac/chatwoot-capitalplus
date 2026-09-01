# Fallback cuando Aircall AI no está disponible (add-on no contratado — confirmado 2026-08-31
# contra la cuenta real del cliente, ver Fase 0 del plan) o todavía no está listo tras agotar el
# poll: transcribe la grabación ya adjunta con el pipeline Whisper que este fork ya usa para
# Twilio (Llm::SpeechToTextService). Whisper solo devuelve texto plano (sin diarización, sin
# timestamps por hablante) y las grabaciones de Aircall en esta cuenta son MONO (CONFIRMADO
# 2026-09-01, no se puede diarizar por canal), así que después de transcribir se intenta un
# best-effort de CallAnalysis::TranscriptSpeakerSplitService para dividir el bloque en turnos
# agente/contacto ADIVINADOS por el LLM — si falla, se queda el bloque sin dividir
# (role_hint: nil en ambos casos) para que el resto del pipeline
# (Voice::ConversationMetricsCalculator, CallAnalysis::StructuredAnalysisLlmService) siga
# funcionando sin cambios — talk_ratio y CTA degradan a "no calculable con precisión" en vez de
# tirar un número inventado, con o sin la división de turnos.
class Crm::Aircall::WhisperTranscriptFallbackService
  def initialize(call:)
    @call = call
  end

  # true si quedó una transcripción utilizable (de esta corrida o de una previa); false si no hay
  # grabación, no hay créditos/feature de Captain, o el audio excede el límite de tamaño — en
  # cualquiera de esos casos CallAnalysis::AnalyzeJob terminará marcando transcript_unavailable.
  def perform
    return true if call.transcript_segments.present?
    return false unless call.recording.attached?
    return false unless Llm::SpeechToTextService.available_for?(call.account)
    return false if Llm::SpeechToTextService.too_large?(call.recording.blob)

    text = Llm::SpeechToTextService.new(blob: call.recording.blob, account: call.account).perform
    return false if text.blank?

    persist!(text)
    CallAnalysis::TranscriptSpeakerSplitService.new(call: call).perform
    true
  end

  private

  attr_reader :call

  def persist!(text)
    call.update!(
      transcript_segments: [{
        'speaker' => 'Transcripción', 'role_hint' => nil,
        'start_seconds' => 0, 'end_seconds' => call.duration_seconds || 0, 'text' => text
      }],
      transcript: text,
      transcript_source: 'whisper_fallback'
    )
  end
end
