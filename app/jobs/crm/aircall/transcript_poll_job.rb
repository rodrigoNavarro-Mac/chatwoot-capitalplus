# Reintenta obtener la transcripción de Aircall AI con backoff hasta MAX_ATTEMPTS veces — cubre
# el caso ":pending" (Aircall AI todavía procesando el audio, ver Crm::Aircall::TranscriptFetchService).
# Si en algún momento el estado pasa a ":unavailable" (403 — cuenta sin el add-on, o se cayó a
# mitad de la llamada), no sigue reintentando: cae directo al fallback de Whisper. Si se agota el
# límite de intentos todavía en ":pending", también cae al fallback antes de rendirse — evita
# depender solo del reintento ciego que dejaba error_step: transcript_unavailable sin más.
class Crm::Aircall::TranscriptPollJob < ApplicationJob
  queue_as :low

  MAX_ATTEMPTS = 10 # ~ backoff exponencial de 1..10 -> cerca de 30 minutos totales

  retry_on Crm::Aircall::Api::TranscriptionClient::ApiError, wait: :polynomially_longer, attempts: 5

  def perform(call_id, attempt: 1)
    call = Call.find_by(id: call_id)
    return if call.blank?

    case Crm::Aircall::TranscriptFetchService.new(call: call).perform
    when :ready
      CallAnalysis::AnalyzeJob.perform_later(call.id)
    when :unavailable
      fall_back_to_whisper!(call)
    when :pending
      continue_or_fall_back!(call, attempt)
    end
  end

  private

  def continue_or_fall_back!(call, attempt)
    if attempt >= MAX_ATTEMPTS
      fall_back_to_whisper!(call)
    else
      self.class.set(wait: (attempt * 2).minutes).perform_later(call.id, attempt: attempt + 1)
    end
  end

  def fall_back_to_whisper!(call)
    Crm::Aircall::WhisperTranscriptFallbackService.new(call: call).perform
    CallAnalysis::AnalyzeJob.perform_later(call.id) # deja que AnalyzeJob marque transcript_unavailable si el fallback tampoco pudo
  end
end
