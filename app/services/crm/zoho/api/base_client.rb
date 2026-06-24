class Crm::Zoho::Api::BaseClient
  include HTTParty

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
    @datacenter = hook.settings['datacenter'].presence || 'com'
    @token_service = Crm::Zoho::TokenRefreshService.new(hook)
    @base_uri = "https://www.zohoapis.#{@datacenter}/crm/v7"
  end

  def get(path, params = {})
    request(:get, path, query: params)
  end

  def post(path, body = {})
    request(:post, path, body: body.to_json)
  end

  def put(path, body = {})
    request(:put, path, body: body.to_json)
  end

  private

  def request(method, path, options = {})
    url = "#{@base_uri}/#{path}"
    response = self.class.send(method, url, options.merge(headers: auth_headers))

    if response.code == 401
      @token_service.invalidate!
      response = self.class.send(method, url, options.merge(headers: auth_headers))
    end

    handle_response(response)
  end

  def auth_headers
    {
      'Authorization' => "Zoho-oauthtoken #{@token_service.token}",
      'Content-Type' => 'application/json'
    }
  end

  def handle_response(response)
    unless response.success?
      raise ApiError.new("Zoho CRM API error: #{response.code} - #{response.body}", response.code, response)
    end

    response.parsed_response || {}
  rescue JSON::ParserError => e
    raise ApiError.new("Failed to parse Zoho CRM response: #{e.message}", response.code, response)
  end
end
