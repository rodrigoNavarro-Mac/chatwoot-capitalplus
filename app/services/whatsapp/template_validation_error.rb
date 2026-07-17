class Whatsapp::TemplateValidationError < StandardError
  attr_reader :details

  def initialize(details)
    @details = Array(details).map { |d| { field: d[:field].to_s, message: d[:message].to_s } }
    super(@details.map { |d| "#{d[:field]}: #{d[:message]}" }.join('; ').presence || 'invalid_template_payload')
  end
end
