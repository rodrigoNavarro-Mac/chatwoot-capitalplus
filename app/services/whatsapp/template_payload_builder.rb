# Builds the full `template.components` array Meta's WhatsApp Cloud API expects, from a
# normalized header hash, a body_params array (plain strings or typed hashes), and a
# button_params array. Doesn't know about any specific template name — it only reacts to the
# shape of what it's given, so it works the same for every approved template.
class Whatsapp::TemplatePayloadBuilder
  def initialize(header: nil, body_params: [], button_params: [], named_parameter_keys: nil)
    @header = header
    @body_params = Array(body_params)
    @button_params = Array(button_params)
    @named_parameter_keys = named_parameter_keys
  end

  def call
    components = []

    header_component = Whatsapp::TemplateHeaderBuilder.new.call(@header)
    components << header_component if header_component

    body_component = build_body_component
    components << body_component if body_component

    components.concat(Whatsapp::TemplateButtonBuilder.new.call(@button_params))

    components
  end

  private

  def build_body_component
    return nil if @body_params.blank?

    parameters = @body_params.each_with_index.map { |param, index| build_body_parameter(param, index) }
    return nil if parameters.blank?

    { type: 'body', parameters: parameters }
  end

  def build_body_parameter(param, index)
    name = @named_parameter_keys && @named_parameter_keys[index]

    case param
    when Hash
      build_typed_body_parameter(param.stringify_keys, index, name)
    else
      text = param.to_s
      name ? parameter_builder.build_named_parameter(name, text) : parameter_builder.build_parameter(text)
    end
  end

  def build_typed_body_parameter(param, index, name)
    case param['type']
    when 'text'
      build_typed_text_parameter(param, index, name)
    when 'currency'
      build_typed_currency_parameter(param, index)
    when 'date_time'
      build_typed_date_time_parameter(param, index)
    else
      raise validation_error("body_params[#{index}].type", "unknown body parameter type: #{param['type'].inspect}")
    end
  end

  def build_typed_text_parameter(param, index, name)
    text = param['text'].to_s
    raise validation_error("body_params[#{index}].text", 'is required for text parameter') if text.blank?

    name ? parameter_builder.build_named_parameter(name, text) : parameter_builder.build_parameter(text)
  end

  def build_typed_currency_parameter(param, index)
    currency = param['currency'].to_h.stringify_keys
    %w[fallback_value code amount_1000].each do |key|
      next if present_or_zero?(currency[key])

      raise validation_error("body_params[#{index}].currency.#{key}", 'is required for currency parameter')
    end

    parameter_builder.build_parameter({ 'type' => 'currency' }.merge(currency))
  end

  def present_or_zero?(value)
    value.present? || value == 0 # rubocop:disable Style/NumericPredicate -- value may be nil, which doesn't respond to #zero?
  end

  def build_typed_date_time_parameter(param, index)
    date_time = param['date_time'].to_h.stringify_keys
    if date_time['fallback_value'].blank?
      raise validation_error("body_params[#{index}].date_time.fallback_value",
                             'is required for date_time parameter')
    end

    parameter_builder.build_parameter({ 'type' => 'date_time' }.merge(date_time))
  end

  def parameter_builder
    @parameter_builder ||= Whatsapp::PopulateTemplateParametersService.new
  end

  def validation_error(field, message)
    Whatsapp::TemplateValidationError.new([{ field: field, message: message }])
  end
end
