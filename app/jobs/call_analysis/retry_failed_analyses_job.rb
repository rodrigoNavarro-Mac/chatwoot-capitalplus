# Reencola los análisis en `failed` con intentos por debajo del límite — cubre errores
# transitorios (timeout de Aircall, rate limit del LLM) sin intervención manual. No usa
# `retry_on` de ActiveJob a propósito: eso escondería el fallo hasta agotar reintentos sin dejarlo
# visible en la cola de revisión (ver CallAnalysis.needs_review) mientras tanto.
class CallAnalysis::RetryFailedAnalysesJob < ApplicationJob
  queue_as :scheduled_jobs

  MAX_ATTEMPTS = 5

  def perform
    CallAnalysis.retryable(MAX_ATTEMPTS).find_each do |record|
      CallAnalysis::AnalyzeJob.perform_later(record.call_id)
    end
  end
end
