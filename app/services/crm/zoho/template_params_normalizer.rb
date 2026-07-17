# Normalizes the payload a Zoho CRM Deluge function sends into the canonical shape
# Whatsapp::TemplatePayloadBuilder expects: a single `header` hash (or nil), body_params,
# and button_params.
#
# Prefers the new `header` object when present. Falls back to the legacy top-level fields
# (header_image_url, header_video_url, header_document_url(+filename), header_text,
# header_location) that existing Deluge functions already send, so nothing already in
# production needs to change. Rejects payloads that mix more than one header source.
class Crm::Zoho::TemplateParamsNormalizer
  def initialize(raw_params)
    @params = if raw_params.is_a?(ActionController::Parameters)
                raw_params.to_unsafe_h.with_indifferent_access
              else
                raw_params.to_h.with_indifferent_access
              end
  end

  def normalize
    {
      header: normalized_header,
      body_params: Array(@params[:body_params]),
      button_params: Array(@params[:button_params])
    }
  end

  private

  def normalized_header
    new_header = @params[:header]
    legacy_headers = detect_legacy_headers
    validate_single_header_source!(new_header, legacy_headers)

    return normalize_new_header(new_header) if new_header.present?

    legacy_headers.first&.fetch(:header)
  end

  def validate_single_header_source!(new_header, legacy_headers)
    if new_header.present? && legacy_headers.any?
      raise conflict_error(['header'] + legacy_headers.pluck(:source))
    elsif legacy_headers.size > 1
      raise conflict_error(legacy_headers.pluck(:source))
    end
  end

  def detect_legacy_headers
    [
      legacy_image_header,
      legacy_video_header,
      legacy_document_header,
      legacy_text_header,
      legacy_location_header
    ].compact
  end

  def legacy_image_header
    return nil if @params[:header_image_url].blank?

    { source: 'header_image_url', header: { 'type' => 'image', 'link' => @params[:header_image_url] } }
  end

  def legacy_video_header
    return nil if @params[:header_video_url].blank?

    { source: 'header_video_url', header: { 'type' => 'video', 'link' => @params[:header_video_url] } }
  end

  def legacy_document_header
    return nil if @params[:header_document_url].blank?

    {
      source: 'header_document_url',
      header: {
        'type' => 'document',
        'link' => @params[:header_document_url],
        'filename' => @params[:header_document_filename]
      }
    }
  end

  def legacy_text_header
    return nil if @params[:header_text].blank?

    { source: 'header_text', header: { 'type' => 'text', 'text' => @params[:header_text] } }
  end

  def legacy_location_header
    return nil if @params[:header_location].blank?

    { source: 'header_location', header: { 'type' => 'location' }.merge(@params[:header_location].to_h.stringify_keys) }
  end

  def normalize_new_header(header)
    normalized = header.to_h.stringify_keys
    normalized['type'] = normalized['type'].to_s.downcase
    normalized
  end

  def conflict_error(sources)
    Whatsapp::TemplateValidationError.new([
                                            { field: 'header',
                                              message: "multiple header sources provided simultaneously: #{sources.uniq.join(', ')}" }
                                          ])
  end
end
