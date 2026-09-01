# Cuando la transcripción viene del fallback de Whisper (un solo bloque sin diarizar — no hay
# licencia de Aircall AI, y CONFIRMADO 2026-09-01 que las grabaciones de esta cuenta son mono, así
# que tampoco se puede diarizar por canal de audio), este servicio le pide al LLM que ADIVINE los
# turnos de conversación (agente/contacto) a partir del texto plano, con pistas de guion de ventas.
#
# Es una ESTIMACIÓN, nunca diarización real — por eso NO se le pone `role_hint` a los segmentos
# resultantes (Voice::ConversationMetricsCalculator solo calcula talk_ratio/cta cuando TODOS los
# segmentos traen role_hint; dejarlo en nil preserva el mismo degradado seguro a `nil` que ya
# documenta esa clase, en vez de alimentarla con duración inventada por turno). El único propósito
# es mejorar la legibilidad de la transcripción en el modal de detalle y ayudar al LLM de análisis
# a atribuir citas — StructuredAnalysisLlmService igual recibe una nota explícita de que es una
# división estimada, no verificada (ver Call#transcript_source == 'whisper_fallback_llm_split').
class CallAnalysis::TranscriptSpeakerSplitService < Llm::BaseAiService
  def initialize(call:)
    super()
    @call = call
  end

  # true si logró dividir y guardar los turnos estimados; false si falla (el fallback de Whisper de
  # un solo bloque, ya guardado por WhisperTranscriptFallbackService, se queda tal cual).
  def perform
    return false if call.transcript.blank?

    turns = fetch_turns
    return false if turns.blank?

    persist!(turns)
    true
  rescue RubyLLM::Error, JSON::ParserError => e
    ChatwootExceptionTracker.new(e, account: call.account).capture_exception
    false
  end

  private

  attr_reader :call

  def fetch_turns
    response = chat.with_params(response_format: { type: 'json_object' })
                   .with_instructions(system_prompt)
                   .ask(call.transcript)
    parsed = JSON.parse(sanitize_json_response(response.content))
    Array(parsed['turns']).select { |t| t.is_a?(Hash) && t['text'].present? && t['speaker'].in?(%w[agent contact]) }
  end

  def persist!(turns)
    segments = turns.each_with_index.map do |turn, index|
      { 'speaker' => (turn['speaker'] == 'agent' ? 'Agente' : 'Cliente'),
        'role_hint' => nil, 'start_seconds' => index, 'end_seconds' => index + 1, 'text' => turn['text'] }
    end

    call.update!(transcript_segments: segments, transcript_source: 'whisper_fallback_llm_split')
  end

  def system_prompt
    <<~PROMPT
      Recibes la transcripción de UNA llamada de ventas inmobiliarias entre un agente (Setter o
      Asesor de una inmobiliaria) y un contacto/lead, transcrita SIN separación de hablante (un
      solo bloque de texto). Tu tarea es dividirla en turnos de conversación, adivinando quién
      habla en cada turno: "agent" (el vendedor de la inmobiliaria) o "contact" (el cliente/lead).

      Pistas típicas del agente: se presenta, dice de qué desarrollo/inmobiliaria llama, hace
      preguntas de calificación (presupuesto, forma de pago, momento de compra), ofrece agendar
      una visita, describe el desarrollo/lotes/precios.
      Pistas típicas del contacto: responde preguntas, expresa dudas o interés, da su presupuesto
      o preferencias, hace preguntas sobre el desarrollo.

      Reglas:
      - Nunca parafrasees ni resumas — copia el texto EXACTO de la transcripción en cada turno.
      - Divide en tantos turnos como haga falta para no mezclar dos intervenciones distintas.
      - Si genuinamente no puedes decidir quién habla en un turno, tu mejor adivinanza es
        aceptable — nunca omitas texto de la transcripción original.

      Responde ÚNICAMENTE con JSON: {"turns": [{"speaker": "agent"|"contact", "text": "..."}]}.
    PROMPT
  end
end
