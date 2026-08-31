# Reintenta obtener la transcripción de Aircall AI con backoff hasta MAX_ATTEMPTS veces (cubre el
# caso en que `call.ended` llega antes de que Aircall AI termine de procesar el audio). Si se
# agota sin éxito, deja el análisis en `failed`/`error_step: transcript_unavailable` en vez de
# reintentar indefinidamente — queda visible en la cola de revisión (ver CallAnalysis::AnalyzeJob).
class Crm::Aircall::TranscriptPollJob < ApplicationJob
  queue_as :low

  MAX_ATTEMPTS = 10 # ~ backoff exponencial de 1..10 -> cerca de 30 minutos totales

  retry_on Crm::Aircall::Api::TranscriptionClient::ApiError, wait: :polynomially_longer, attempts: 5

  def perform(call_id, attempt: 1)
    call = Call.find_by(id: call_id)
    return if call.blank?

    if Crm::Aircall::TranscriptFetchService.new(call: call).perform
      CallAnalysis::AnalyzeJob.perform_later(call.id)
      return
    end

    if attempt >= MAX_ATTEMPTS
      CallAnalysis::AnalyzeJob.perform_later(call.id) # deja que AnalyzeJob marque error_step: transcript_unavailable
      return
    end

    self.class.set(wait: (attempt * 2).minutes).perform_later(call_id, attempt: attempt + 1)
  end
end
