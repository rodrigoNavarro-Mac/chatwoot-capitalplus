# Se encola desde Crm::Aircall::CallProcessor cuando una llamada de Aircall termina completada —
# adjunta la grabación y, si Aircall AI ya tiene la transcripción lista, dispara el análisis. Si
# la transcripción todavía no está lista (Aircall AI puede tardar más que los ~30s de
# `call.ended`), agenda Crm::Aircall::TranscriptPollJob en vez de fallar.
class Crm::Aircall::RecordingAndTranscriptJob < ApplicationJob
  queue_as :low

  def perform(call_id, recording_url: nil)
    call = Call.find_by(id: call_id)
    return if call.blank?

    Crm::Aircall::RecordingAttachmentService.new(call: call, recording_url: recording_url).perform if recording_url.present?

    if Crm::Aircall::TranscriptFetchService.new(call: call).perform
      CallAnalysis::AnalyzeJob.perform_later(call.id)
    else
      Crm::Aircall::TranscriptPollJob.perform_later(call.id)
    end
  rescue StandardError => e
    Rails.logger.error("[AIRCALL] RecordingAndTranscriptJob failed for call ##{call_id}: #{e.message}")
    ChatwootExceptionTracker.new(e, account: call&.account).capture_exception
  end
end
