# Cliente REST del endpoint de transcripción de Aircall AI (`GET /v1/calls/:id/transcription`,
# developer.aircall.io/docs/log-transcriptions — requiere el add-on "AI Assist" contratado en la
# cuenta de Aircall; sin él, este endpoint devuelve 403). Mismo Basic Auth que
# Crm::Aircall::Api::CallsClient (api_id/api_token en Integrations::Hook#settings).
#
# CONFIRMADO 2026-08-31 contra la cuenta real de producción (account_id 2), probado contra varias
# llamadas reales de ese mismo día, incluida una con transcripción visible en el dashboard de
# Aircall: siempre 403 con body `{"message":"Forbidden access: company is not verified."}` — no es
# "aún procesando" ni "endpoint equivocado", es un paso de verificación de la empresa que exige
# Aircall antes de dar acceso a esta API (aparte de si el add-on AI Assist está pagado), y el
# cliente decidió no perseguirlo. Por eso el pipeline SIEMPRE cae al fallback de Whisper
# (Crm::Aircall::WhisperTranscriptFallbackService) en este cliente — este intento se deja igual
# (falla al instante, sin costo) para que, si algún día Aircall completa esa verificación sin
# que haya que tocar código aquí, el pipeline empiece a usarlo automáticamente.
#
# Shape real confirmado contra la documentación oficial de Aircall (2026-08-31, ver Fase 0 del
# plan de análisis de llamadas):
#   { "transcription": { "id":, "call_id":, "content": { "language":, "utterances": [
#       { "start_time": 12.54, "end_time": 13.8, "text": "...",
#         "participant_type": "internal"|"external", "user_id": 123 | "phone_number": "+..." }
#   ] } } }
# `participant_type` da directo quién es el agente ("internal") y quién el contacto ("external")
# — se usa como fuente de verdad para role_hint en vez de adivinar por nombre.
class Crm::Aircall::Api::TranscriptionClient
  include HTTParty

  base_uri 'https://api.aircall.io/v1'

  INTERNAL_PARTICIPANT = 'internal'.freeze
  EXTERNAL_PARTICIPANT = 'external'.freeze
  ROLE_HINT_BY_PARTICIPANT_TYPE = { INTERNAL_PARTICIPANT => 'agent', EXTERNAL_PARTICIPANT => 'external' }.freeze

  class ApiError < StandardError
    attr_reader :code, :response

    def initialize(message = nil, code = nil, response = nil)
      @code = code
      @response = response
      super(message)
    end
  end

  # Aircall AI no está contratado para esta cuenta — 403 permanente, distinto de "aún procesando"
  # (202/404), para que TranscriptFetchService decida "cae al fallback de Whisper" en vez de
  # "reintentar con backoff" (ver Crm::Aircall::WhisperTranscriptFallbackService).
  class NotAvailableError < ApiError; end

  def initialize(hook)
    @hook = hook
  end

  # Devuelve un array de segmentos normalizados `{speaker:, role_hint:, start_seconds:, end_seconds:, text:}`,
  # ordenados por start_seconds, o [] si la transcripción aún no está lista (202/404 antes de que
  # Aircall AI termine de procesar).
  def fetch_segments(aircall_call_id)
    response = raw_response(aircall_call_id)

    return [] if response.code.in?([202, 404])
    raise NotAvailableError.new('Aircall AI no contratado para esta cuenta', response.code, response) if response.code == 403

    handle_response(response)
  end

  # Devuelve la respuesta HTTP sin normalizar — solo para validar manualmente el shape real de
  # Aircall AI contra una llamada real (ver lib/tasks/validate_aircall_transcription_api.rake, y
  # el comentario de cabecera de esta clase). No la use el pipeline automático.
  def raw_response(aircall_call_id)
    self.class.get(
      "/calls/#{aircall_call_id}/transcription",
      basic_auth: { username: api_id, password: api_token }
    )
  end

  private

  attr_reader :hook

  def api_id
    hook.settings['api_id']
  end

  def api_token
    hook.settings['api_token']
  end

  def handle_response(response)
    raise ApiError.new("Aircall transcription API error: #{response.code} - #{response.body}", response.code, response) unless response.success?

    normalize_utterances(response.parsed_response)
  rescue JSON::ParserError => e
    raise ApiError.new("Failed to parse Aircall transcription response: #{e.message}", response.code, response)
  end

  def normalize_utterances(payload)
    raw = extract_utterances_array(payload)
    raw.filter_map { |utterance| normalize_utterance(utterance) }.sort_by { |seg| seg[:start_seconds] }
  end

  # `transcription.content.utterances` es el shape real confirmado; se conservan un par de
  # fallbacks defensivos por si Aircall cambia el envoltorio en otro tipo de transcripción
  # (`type` puede ser "call" o "voicemail" según la doc) sin romper en silencio.
  def extract_utterances_array(payload)
    return payload if payload.is_a?(Array)
    return [] unless payload.is_a?(Hash)

    payload.dig('transcription', 'content', 'utterances') ||
      payload.dig('content', 'utterances') ||
      payload['utterances'] || []
  end

  def normalize_utterance(utterance)
    return nil unless utterance.is_a?(Hash)

    text = utterance['text']
    return nil if text.blank?

    role_hint = ROLE_HINT_BY_PARTICIPANT_TYPE[utterance['participant_type']]

    {
      speaker: role_hint == 'agent' ? 'Agente' : 'Cliente',
      role_hint: role_hint,
      start_seconds: timestamp(utterance['start_time']),
      end_seconds: timestamp(utterance['end_time']),
      text: text.to_s.strip
    }
  end

  def timestamp(value)
    value.present? ? value.to_f.round : nil
  end
end
