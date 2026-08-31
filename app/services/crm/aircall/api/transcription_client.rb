# Cliente REST del endpoint de transcripción de Aircall AI (`GET /v1/calls/:id/transcription`,
# developer.aircall.io/docs/log-transcriptions — requiere el add-on "AI Assist" contratado en la
# cuenta de Aircall; sin él, este endpoint devuelve 403/404 según confirma la documentación de
# soporte). Mismo Basic Auth que Crm::Aircall::Api::CallsClient (api_id/api_token en
# Integrations::Hook#settings) — la documentación pública también admite OAuth, pero no hay
# necesidad de un segundo mecanismo de credenciales mientras Basic Auth funcione.
#
# El shape exacto del JSON de utterances no está publicado en la documentación pública de Aircall
# al momento de escribir esto — #normalize_utterances es defensivo y acepta varias formas
# plausibles (ver comentario ahí) en vez de asumir una sola. Ajustar esa normalización en cuanto
# se valide contra una respuesta real de la cuenta del cliente (ver Fase 0 del plan).
class Crm::Aircall::Api::TranscriptionClient
  include HTTParty

  base_uri 'https://api.aircall.io/v1'

  class ApiError < StandardError
    attr_reader :code, :response

    def initialize(message = nil, code = nil, response = nil)
      @code = code
      @response = response
      super(message)
    end
  end

  # Aircall AI no está contratado / sin transcripción disponible para esta llamada — distinto de
  # un error de red o de credenciales, para que TranscriptFetchService pueda decidir "no
  # reintentar" en vez de "reintentar con backoff".
  class NotAvailableError < ApiError; end

  def initialize(hook)
    @hook = hook
  end

  # Devuelve un array de segmentos normalizados `{speaker:, start_seconds:, end_seconds:, text:}`,
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

  # Acepta las formas más plausibles documentadas/observadas para "Conversation Intelligence" de
  # Aircall: un array top-level de utterances, o un hash con `data`/`utterances`/`sentences`
  # envolviendo ese array. Cada utterance puede traer el hablante bajo `speaker`, `participant`, o
  # `participant.name`; el timestamp bajo `start_time`/`start`/`offset` en segundos.
  def normalize_utterances(payload)
    raw = extract_utterances_array(payload)
    raw.filter_map { |utterance| normalize_utterance(utterance) }.sort_by { |seg| seg[:start_seconds] }
  end

  def extract_utterances_array(payload)
    return payload if payload.is_a?(Array)
    return [] unless payload.is_a?(Hash)

    payload['data'] || payload['utterances'] || payload['sentences'] || payload.dig('data', 'utterances') || []
  end

  def normalize_utterance(utterance)
    return nil unless utterance.is_a?(Hash)

    text = utterance['text'] || utterance['content']
    return nil if text.blank?

    {
      speaker: speaker_label(utterance),
      start_seconds: timestamp(utterance, %w[start_time start offset]),
      end_seconds: timestamp(utterance, %w[end_time end]),
      text: text.to_s.strip
    }
  end

  def speaker_label(utterance)
    speaker = utterance['speaker'] || utterance['participant']
    return speaker if speaker.is_a?(String)
    return speaker['name'] || speaker['user_id'] || speaker['type'] if speaker.is_a?(Hash)

    'unknown'
  end

  def timestamp(utterance, keys)
    value = keys.filter_map { |key| utterance[key] }.first
    value.present? ? value.to_f.round : nil
  end
end
