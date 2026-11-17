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

  protected

  # Zoho stores the number in either field depending on how the record was
  # created (agents commonly load the WhatsApp number under "Mobile").
  PHONE_FIELDS = %w[Phone Mobile].freeze

  # Builds a Zoho "criteria" query that matches a record by email or by phone.
  # Uses field-level exact matching (unlike the `word` full-text search, this
  # does not depend on the module's Search Layout configuration) and compares
  # the phone number in a few common formats (E.164, digits only, national
  # number without country code) since Zoho records are often entered by hand
  # without the "+" or the country code, against both the Phone and Mobile
  # fields.
  def search_criteria(email: nil, phone: nil)
    clauses = []
    clauses << "(Email:equals:#{email})" if email.present?
    phone_variants(phone).each do |value|
      PHONE_FIELDS.each { |field| clauses << "(#{field}:equals:#{value})" }
    end

    return nil if clauses.empty?
    return clauses.first if clauses.size == 1

    "(#{clauses.join('or')})"
  end

  private

  MX_COUNTRY_CODE = '52'.freeze
  MX_LOCAL_LENGTH = 10

  # Los leads de Meta/Google Ads llegan a Zoho con el número local de 10 dígitos, sin lada de país
  # (ej. "9037469027"), mientras Chatwoot guarda el contacto en E.164 ("+529037469027" o, con el
  # prefijo móvil viejo, "+5214423623823"). La variante "national" de abajo depende de que
  # TelephoneNumber considere el número válido -- y un número mal capturado o con lada que no
  # existe en México (ej. 903, que es de Texas) no lo es, así que la búsqueda no encontraba el lead
  # de Meta y ContactFinderService creaba un duplicado (caso real 2026-11-15, Belem Gaona). Para
  # +521 la variante "national" además conserva el "1" ("14423623823"), que tampoco coincide.
  # Por eso para cualquier número +52 se agregan siempre los 10 dígitos locales y su E.164 sin el
  # "1", sin depender de la validación.
  def mexican_local_variants(digits)
    return [] unless digits.start_with?(MX_COUNTRY_CODE)
    return [] unless digits.length.between?(MX_COUNTRY_CODE.length + MX_LOCAL_LENGTH, MX_COUNTRY_CODE.length + MX_LOCAL_LENGTH + 1)

    local = digits.last(MX_LOCAL_LENGTH)
    [local, "+#{MX_COUNTRY_CODE}#{local}"]
  end

  def phone_variants(phone)
    return [] if phone.blank?

    digits = phone.delete('+')
    variants = [phone, digits]

    variants.concat(mexican_local_variants(digits))

    parsed = TelephoneNumber.parse(phone)
    if parsed.valid?
      national = digits.sub(/\A#{Regexp.escape(parsed.country.country_code)}/, '')
      variants << national if national.present?
    end

    variants.uniq
  rescue StandardError
    [phone, *mexican_local_variants(phone.to_s.delete('+'))].uniq
  end

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

    parsed = response.parsed_response || {}

    if parsed.is_a?(Hash) && parsed['data'].is_a?(Array)
      error_entry = parsed['data'].find { |d| d.is_a?(Hash) && d['status'] == 'error' }
      if error_entry
        raise ApiError.new(
          "Zoho CRM error: #{error_entry['message']} (#{error_entry['code']})",
          response.code,
          response
        )
      end
    end

    parsed
  rescue JSON::ParserError => e
    raise ApiError.new("Failed to parse Zoho CRM response: #{e.message}", response.code, response)
  end
end
