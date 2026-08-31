# Punto de entrada para el webhook de Aircall en tiempo real.
#
# `call.ended` (Aircall lo dispara ~30s después de colgar, ya con duración/grabación resueltas —
# ver developer.aircall.io/tutorials/webhooks-guide) delega el procesamiento del call object a
# Crm::Aircall::CallProcessor, compartido con Crm::Aircall::CallHistoryBackfillService (backfill
# histórico vía la REST API) para que ambos flujos reflejen una llamada de forma idéntica.
#
# `transcription.created` (Aircall AI, solo si el add-on está contratado — ver
# developer.aircall.io/docs/log-transcriptions) llega por separado y más tarde que `call.ended`
# porque el procesamiento de IA toma más tiempo; el payload de este evento NO incluye la
# transcripción en sí, solo el id de la llamada, así que se resuelve con un GET aparte vía
# Crm::Aircall::TranscriptFetchService en vez de pasar por CallProcessor de nuevo.
class Crm::Aircall::InboundWebhookService
  CALL_ENDED_EVENT = 'call.ended'.freeze
  TRANSCRIPTION_CREATED_EVENT = 'transcription.created'.freeze

  def initialize(account, params)
    @account = account
    @params = params.with_indifferent_access
  end

  def perform
    case event
    when CALL_ENDED_EVENT
      Crm::Aircall::CallProcessor.new(account: account, call_data: data).perform
    when TRANSCRIPTION_CREATED_EVENT
      handle_transcription_created
    end
  end

  private

  attr_reader :account, :params

  def event
    params[:event]
  end

  def data
    params[:data] || {}
  end

  def handle_transcription_created
    return unless account.feature_enabled?('call_intelligence')

    call = Call.find_by_provider_call_id(:aircall, data[:call_id].to_s)
    return if call.blank?

    Crm::Aircall::RecordingAndTranscriptJob.perform_later(call.id)
  end
end
