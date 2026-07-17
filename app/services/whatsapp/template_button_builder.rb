# Builds `button` components of a WhatsApp Cloud API template payload from a `button_params`
# array. Only buttons that actually need runtime parameters should be included by the caller —
# static buttons (a fixed phone number, a URL with no variable) don't need an entry here.
#
# Extensible by subtype: add a new key to BUILDERS (and the matching private method) to support
# a new Meta button subtype without touching the orchestrator or the controller.
class Whatsapp::TemplateButtonBuilder
  BUILDERS = {
    'quick_reply' => :build_quick_reply,
    'url' => :build_url,
    'flow' => :build_flow
  }.freeze

  def call(button_params)
    Array(button_params).each_with_index.map { |button, position| build(button, position) }
                        .sort_by { |component| component[:index].to_i }
  end

  private

  def build(button, position)
    button = button.to_h.stringify_keys
    type = button['type'].to_s.downcase
    index = button['index']
    raise validation_error("button_params[#{position}].index", 'is required') if index.nil?

    builder_method = BUILDERS[type]
    raise validation_error("button_params[#{position}].type", "unknown button subtype: #{type.inspect}") unless builder_method

    send(builder_method, button, index, position)
  end

  def build_quick_reply(button, index, position)
    payload = button['payload'].to_s
    raise validation_error("button_params[#{position}].payload", 'is required for quick_reply button') if payload.blank?

    {
      type: 'button',
      sub_type: 'quick_reply',
      index: index.to_s,
      parameters: [{ type: 'payload', payload: payload }]
    }
  end

  def build_url(button, index, position)
    text = button['text'].to_s
    raise validation_error("button_params[#{position}].text", 'is required for url button') if text.blank?

    {
      type: 'button',
      sub_type: 'url',
      index: index.to_s,
      parameters: [{ type: 'text', text: text }]
    }
  end

  def build_flow(button, index, position)
    flow_token = button['flow_token'].to_s
    raise validation_error("button_params[#{position}].flow_token", 'is required for flow button') if flow_token.blank?

    action = { flow_token: flow_token }
    action[:flow_action_data] = button['flow_action_data'] if button['flow_action_data'].present?

    {
      type: 'button',
      sub_type: 'flow',
      index: index.to_s,
      parameters: [{ type: 'action', action: action }]
    }
  end

  def validation_error(field, message)
    Whatsapp::TemplateValidationError.new([{ field: field, message: message }])
  end
end
