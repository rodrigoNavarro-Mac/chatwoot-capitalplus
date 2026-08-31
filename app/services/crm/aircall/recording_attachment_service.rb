# Descarga y adjunta la grabación de una llamada de Aircall a `call.recording` — mismo patrón que
# Voice::Provider::Twilio::RecordingAttachmentService, pero Aircall ya manda la URL de la
# grabación directamente en el call object (`recording`, ver developer.aircall.io/api-references)
# sin necesidad de un segundo request para resolverla, y sin auth_token por canal: se usa el mismo
# Basic Auth (api_id/api_token) que el resto de la API de Aircall.
class Crm::Aircall::RecordingAttachmentService
  ALLOWED_CONTENT_TYPE_PREFIXES = %w[audio/].freeze
  DEFAULT_FILENAME_EXTENSION = 'wav'.freeze

  def initialize(call:, recording_url:)
    @call = call
    @recording_url = recording_url
  end

  def perform
    return if recording_url.blank? || call.recording.attached?

    SafeFetch.fetch(
      recording_url,
      http_basic_authentication: [api_id, api_token],
      allowed_content_type_prefixes: ALLOWED_CONTENT_TYPE_PREFIXES
    ) do |result|
      call.recording.attach(io: result.tempfile, filename: recording_filename(result), content_type: recording_content_type(result))
    end
  end

  private

  attr_reader :call, :recording_url

  def hook
    @hook ||= call.account.hooks.find_by(app_id: 'aircall', status: 'enabled')
  end

  def api_id
    hook&.settings&.dig('api_id')
  end

  def api_token
    hook&.settings&.dig('api_token')
  end

  def recording_filename(result)
    return result.original_filename if result.original_filename.present?

    "aircall-call-#{call.provider_call_id}.#{recording_extension(result)}"
  end

  def recording_extension(result)
    content_type = recording_content_type(result)
    Rack::Mime::MIME_TYPES.invert[content_type].to_s.delete_prefix('.').presence || DEFAULT_FILENAME_EXTENSION
  end

  def recording_content_type(result)
    result.content_type.presence || 'audio/wav'
  end
end
