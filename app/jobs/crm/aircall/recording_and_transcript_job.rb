# Se encola desde Crm::Aircall::CallProcessor cuando una llamada de Aircall termina completada —
# adjunta la grabación y resuelve la transcripción: Aircall AI si está lista, el fallback de
# Whisper si Aircall AI no está disponible (403 permanente), o un poll con backoff si Aircall AI
# todavía está procesando (202/404 — puede tardar más que los ~30s de `call.ended`).
class Crm::Aircall::RecordingAndTranscriptJob < ApplicationJob
  queue_as :low

  def perform(call_id, recording_url: nil)
    call = Call.find_by(id: call_id)
    return if call.blank?

    Crm::Aircall::RecordingAttachmentService.new(call: call, recording_url: recording_url).perform if recording_url.present?

    handle_status(call, Crm::Aircall::TranscriptFetchService.new(call: call).perform)
  rescue StandardError => e
    Rails.logger.error("[AIRCALL] RecordingAndTranscriptJob failed for call ##{call_id}: #{e.message}")
    ChatwootExceptionTracker.new(e, account: call&.account).capture_exception
  end

  private

  def handle_status(call, status)
    case status
    when :ready then CallAnalysis::AnalyzeJob.perform_later(call.id)
    when :pending then Crm::Aircall::TranscriptPollJob.perform_later(call.id)
    when :unavailable then fall_back_to_whisper!(call)
    end
  end

  def fall_back_to_whisper!(call)
    Crm::Aircall::WhisperTranscriptFallbackService.new(call: call).perform
    CallAnalysis::AnalyzeJob.perform_later(call.id)
  end
end
