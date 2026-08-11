# Cliente REST del endpoint histórico de Aircall (`GET /v1/calls`), usado por
# Crm::Aircall::CallHistoryBackfillService para traer llamadas ya realizadas — a diferencia de
# Crm::Zoho::Api::BaseClient (OAuth con refresh de token), Aircall usa Basic Auth directo con
# api_id/api_token (developers.aircall.io/tutorials/postman-getting-started), guardados en
# Integrations::Hook#settings junto al webhook_secret.
class Crm::Aircall::Api::CallsClient
  include HTTParty

  base_uri 'https://api.aircall.io/v1'

  PER_PAGE = 50

  class ApiError < StandardError
    attr_reader :code, :response

    def initialize(message = nil, code = nil, response = nil)
      @code = code
      @response = response
      super(message)
    end
  end

  def initialize(hook)
    @hook = hook
  end

  # from/to: Time — se envían como unix timestamps, tal como espera la API de Aircall.
  def list(from:, to:, page: 1)
    response = self.class.get(
      '/calls',
      query: { from: from.to_i, to: to.to_i, page: page, per_page: PER_PAGE, order: 'asc' },
      basic_auth: { username: api_id, password: api_token }
    )

    handle_response(response)
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
    raise ApiError.new("Aircall API error: #{response.code} - #{response.body}", response.code, response) unless response.success?

    response.parsed_response || {}
  rescue JSON::ParserError => e
    raise ApiError.new("Failed to parse Aircall response: #{e.message}", response.code, response)
  end
end
