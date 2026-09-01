# Backfill puntual para llamadas que cayeron al fallback de Whisper ANTES de que existiera
# CallAnalysis::TranscriptSpeakerSplitService (agregado 2026-09-01) — les corre la división en
# turnos estimados ahora, sin volver a analizar scorecard/objeciones/mapa de calificación (ver
# CallAnalysis::AnalyzeJob para el reanálisis completo, que es un flujo aparte y más costoso).
# Seguro de correr dos veces: solo actúa si transcript_source sigue en 'whisper_fallback' —
# una vez dividida, la llamada pasa a 'whisper_fallback_llm_split' y este job la ignora.
class CallAnalysis::SplitWhisperTranscriptJob < ApplicationJob
  queue_as :low

  def perform(call_id)
    call = Call.find_by(id: call_id)
    return if call.blank? || call.transcript_source != 'whisper_fallback'

    CallAnalysis::TranscriptSpeakerSplitService.new(call: call).perform
  end
end
