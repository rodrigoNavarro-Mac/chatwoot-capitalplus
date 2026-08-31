# Obtiene la transcripción diarizada de una llamada de Aircall (Aircall AI) y la guarda en
# `call.transcript_segments` + `call.transcript` (texto plano concatenado, para la burbuja del
# mensaje) + `call.transcript_source = 'aircall_ai'`. Ver Crm::Aircall::Api::TranscriptionClient
# para el shape real y la normalización.
#
# Idempotente: si `call.transcript_segments` ya está presente (por esta fuente o por el fallback
# de Whisper), no vuelve a pedirla — evita gastar cuota de Aircall AI en cada reintento.
class Crm::Aircall::TranscriptFetchService
  def initialize(call:)
    @call = call
  end

  # :ready       — ya hay segmentos guardados (los de esta llamada, o ya estaban de antes).
  # :pending     — Aircall AI todavía no termina de procesar (202/404) — vale la pena reintentar.
  # :unavailable — sin hook, o Aircall AI no contratado (403) — no reintentar, ir al fallback de
  #                Whisper (ver Crm::Aircall::WhisperTranscriptFallbackService).
  def perform
    return :ready if call.transcript_segments.present?
    return :unavailable if hook.blank?

    segments = client.fetch_segments(call.provider_call_id)
    return :pending if segments.blank?

    persist!(segments)
    :ready
  rescue Crm::Aircall::Api::TranscriptionClient::NotAvailableError
    :unavailable
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
      transcript: segments.map { |seg| "#{seg[:speaker]}: #{seg[:text]}" }.join("\n"),
      transcript_source: 'aircall_ai'
    )
  end
end
