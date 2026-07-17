# Sends a built `components` array to Meta's WhatsApp Cloud API for a given channel/phone, and
# translates a failed send into Crm::Zoho::TemplateSendError with a sanitized (no tokens/secrets)
# view of Meta's error payload.
class Crm::Zoho::TemplateSender
  def initialize(channel:, request_id:)
    @channel = channel
    @request_id = request_id
  end

  def call(phone, template_name, template_language, components)
    provider = @channel.provider_service
    wamid = provider.send_template(phone, { name: template_name, lang_code: template_language, parameters: components }, nil)
    return wamid if wamid

    Rails.logger.error("[ZohoCRM][SendTemplate][#{@request_id}] Meta template send failed: #{provider.last_api_error.inspect}")
    raise Crm::Zoho::TemplateSendError.new(
      meta_error: safe_meta_error(provider.last_api_error),
      http_status: meta_http_status(provider.last_api_status)
    )
  end

  private

  def safe_meta_error(error)
    return nil if error.blank?

    {
      message: error['message'],
      code: error['code'],
      type: error['type'],
      details: error.dig('error_data', 'details'),
      fbtrace_id: error['fbtrace_id']
    }.compact
  end

  def meta_http_status(status_code)
    code = status_code.to_i
    return :unprocessable_entity if code.between?(400, 499)

    :bad_gateway
  end
end
