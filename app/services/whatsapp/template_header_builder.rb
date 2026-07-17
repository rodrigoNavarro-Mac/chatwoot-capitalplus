# Builds the `header` component of a WhatsApp Cloud API template payload.
#
# Accepts a normalized header hash with a `type` key (none/text/image/video/document/location,
# case-insensitive) and type-specific fields, and returns the exact component structure Meta
# expects, or nil when no header component should be sent.
class Whatsapp::TemplateHeaderBuilder
  ALLOWED_TYPES = %w[none text image video document location].freeze

  def call(header)
    return nil if header.blank?

    header = header.to_h.stringify_keys
    type = header['type'].to_s.downcase
    validate_type!(type)
    return nil if type == 'none'

    parameters = build_parameters(type, header)
    return nil if parameters.blank?

    { type: 'header', parameters: parameters }
  end

  private

  def validate_type!(type)
    return if ALLOWED_TYPES.include?(type)

    raise validation_error('header.type', "must be one of #{ALLOWED_TYPES.join(', ')}, got #{type.inspect}")
  end

  def build_parameters(type, header)
    case type
    when 'text' then build_text(header)
    when 'location' then build_location(header)
    else build_media(header, type)
    end
  end

  def build_text(header)
    text = header['text'].to_s.strip
    return [] if text.blank?

    [parameter_builder.build_parameter(text)]
  end

  def build_media(header, media_type)
    link = header['link'].presence
    id = header['id'].presence
    field = media_type == 'document' ? 'header.link' : "header.#{media_type}"

    raise validation_error(field, "link or id is required for #{media_type} header") if link.blank? && id.blank?
    raise validation_error(field, 'link and id cannot be used together') if link.present? && id.present?

    if id
      build_media_by_id(media_type, id, header)
    else
      build_media_by_link(media_type, link, header)
    end
  end

  def build_media_by_id(media_type, id, header)
    if media_type == 'document'
      document = { id: id }
      filename = header['filename'].to_s.strip
      document[:filename] = filename if filename.present?
      [{ type: 'document', document: document }]
    else
      [{ :type => media_type, media_type.to_sym => { id: id } }]
    end
  end

  def build_media_by_link(media_type, link, header)
    validate_https!(link, 'header.link')
    media_name = media_type == 'document' ? header['filename'].to_s.strip.presence : nil
    [parameter_builder.build_media_parameter(link, media_type, media_name)]
  rescue ArgumentError => e
    raise validation_error('header.link', e.message)
  end

  def build_location(header)
    latitude = header['latitude']
    longitude = header['longitude']
    raise validation_error('header.latitude', 'is required for location header') if latitude.blank?
    raise validation_error('header.longitude', 'is required for location header') if longitude.blank?

    location = { latitude: latitude, longitude: longitude }
    location[:name] = header['name'] if header['name'].present?
    location[:address] = header['address'] if header['address'].present?

    [{ type: 'location', location: location }]
  end

  def validate_https!(url, field)
    uri = URI.parse(url)
    raise validation_error(field, 'must use https for self-hosted media') unless uri.scheme == 'https'
  rescue URI::InvalidURIError
    raise validation_error(field, 'is not a valid URL')
  end

  def parameter_builder
    @parameter_builder ||= Whatsapp::PopulateTemplateParametersService.new
  end

  def validation_error(field, message)
    Whatsapp::TemplateValidationError.new([{ field: field, message: message }])
  end
end
