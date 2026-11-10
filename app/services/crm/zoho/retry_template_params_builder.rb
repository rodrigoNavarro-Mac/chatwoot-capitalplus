# Construye `processed_params` (formato enhanced, el mismo que guarda el composer de Chatwoot)
# para un mensaje de plantilla enviado desde Zoho.
#
# El botón "Reintentar" del dashboard reenvía el mensaje por el flujo estándar
# (SendReplyJob -> Whatsapp::TemplateProcessorService), que solo entiende `processed_params`.
# Sin esto el reintento salía con 0 parámetros y Meta respondía #132000, tapando el error real
# del primer envío (p. ej. 131049).
#
# Si el payload trae algo que ese flujo no sabe reconstruir (botones dinámicos, header de
# texto/ubicación, body tipado no-texto) devuelve nil: el reintento falla igual que antes,
# sin mandar a Meta una plantilla incompleta.
class Crm::Zoho::RetryTemplateParamsBuilder
  MEDIA_HEADER_TYPES = %w[image video document].freeze

  def initialize(template:, header:, body_params:, button_params:)
    @template = template
    @header = header
    @body_params = Array(body_params)
    @button_params = button_params
  end

  def call
    return nil if @button_params.present?

    body = body_params
    return nil if body.nil?

    header = header_params
    return nil if @header.present? && header.nil?

    { 'body' => body.presence, 'header' => header }.compact
  end

  private

  def body_params
    keys = body_keys
    return nil if keys.size < @body_params.size

    @body_params.each_with_index.to_h do |param, index|
      text = param_text(param)
      return nil if text.nil?

      [keys[index], text]
    end
  end

  def body_keys
    return named_keys if @template['parameter_format'] == 'NAMED'

    (1..@body_params.size).map(&:to_s)
  end

  def named_keys
    body_component = @template['components']&.find { |c| c['type']&.upcase == 'BODY' }
    return [] unless body_component

    named = body_component.dig('example', 'body_text_named_params')
    return named.pluck('param_name') if named.present?

    body_component['text'].to_s.scan(/\{\{(\w+)\}\}/).flatten
  end

  def param_text(param)
    return param.to_s unless param.is_a?(Hash)

    param = param.stringify_keys
    param['type'] == 'text' ? param['text'].to_s : nil
  end

  def header_params
    return nil if @header.blank?
    return nil unless MEDIA_HEADER_TYPES.include?(@header['type']) && @header['link'].present?

    { 'media_url' => @header['link'], 'media_type' => @header['type'], 'media_name' => @header['filename'] }.compact
  end
end
