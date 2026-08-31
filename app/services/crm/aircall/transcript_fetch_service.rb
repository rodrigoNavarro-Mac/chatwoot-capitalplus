# Obtiene la transcripción diarizada de una llamada de Aircall (Aircall AI) y la guarda en
# `call.transcript_segments` + `call.transcript` (texto plano concatenado, para la burbuja del
# mensaje). Ver Crm::Aircall::Api::TranscriptionClient para el detalle de la normalización.
#
# Idempotente: si `call.transcript_segments` ya está presente, no vuelve a pedirla (evita gastar
# cuota/costo de Aircall AI en cada reintento del job que la dispara).
class Crm::Aircall::TranscriptFetchService
  def initialize(call:)
    @call = call
  end

  # true si quedaron segmentos guardados (listos para análisis); false si Aircall AI aún no
  # terminó de procesar la transcripción (el caller decide si reintentar) o si la cuenta no tiene
  # el add-on contratado (el caller no debe reintentar en ese caso).
  def perform
    return true if call.transcript_segments.present?
    return false if hook.blank?

    segments = client.fetch_segments(call.provider_call_id)
    return false if segments.blank?

    persist!(segments)
    true
  rescue Crm::Aircall::Api::TranscriptionClient::NotAvailableError
    false
  end

  private

  attr_reader :call

  def hook
    @hook ||= call.account.hooks.find_by(app_id: 'aircall', status: 'enabled')
  end

  def client
    @client ||= Crm::Aircall::Api::TranscriptionClient.new(hook)
  end

  def persist!(segments)
    call.update!(
      transcript_segments: segments.map(&:stringify_keys),
      transcript: segments.map { |seg| "#{seg[:speaker]}: #{seg[:text]}" }.join("\n")
    )
  end
end
