# Raised when Meta's Graph API rejects a template send. Carries a sanitized (no tokens/secrets)
# view of Meta's error payload so the caller (the Zoho webhook controller) can surface a
# diagnosable response instead of a bare "template_send_failed".
class Crm::Zoho::TemplateSendError < StandardError
  attr_reader :meta_error, :http_status

  def initialize(meta_error: nil, http_status: :bad_gateway)
    @meta_error = meta_error
    @http_status = http_status
    super('template_send_failed')
  end
end
