# Re-pide la URL de grabación de una llamada de Aircall vía GET /v1/calls/:id cuando el webhook
# `call.ended` llegó sin ella (Aircall a veces dispara `call.ended` antes de terminar de subir la
# grabación a su storage — CONFIRMADO 2026-09-01: 9 de 14 llamadas en error_step recording_missing
# duraban entre 22s y 203s, muy largas para asumir "no hubo nada que grabar"). Reintentable sin
# límite por CallAnalysis::AnalyzeJob en cada retry — Aircall conserva la grabación
# indefinidamente, solo la URL pre-firmada expira (~1h), por eso siempre se vuelve a pedir en vez
# de guardarla.
class Crm::Aircall::RecordingRefetchService
  def initialize(call:)
    @call = call
  end

  # true si quedó una grabación adjunta (de esta corrida o de una previa); false si no hay hook, la
  # API de Aircall no tiene una URL para esta llamada, o el fetch falló.
  def perform
    return true if call.recording.attached?
    return false if hook.blank?

    url = fetch_recording_url
    return false if url.blank?

    Crm::Aircall::RecordingAttachmentService.new(call: call, recording_url: url).perform
    call.recording.attached?
  end

  private

  attr_reader :call

  def hook
    @hook ||= call.account.hooks.find_by(app_id: 'aircall', status: 'enabled')
  end

  def fetch_recording_url
    Crm::Aircall::Api::CallsClient.new(hook).show(call.provider_call_id)['recording']
  rescue Crm::Aircall::Api::CallsClient::ApiError => e
    ChatwootExceptionTracker.new(e, account: call.account).capture_exception
    nil
  end
end
