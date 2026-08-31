# Descarga y adjunta la grabación de una llamada de Aircall a `call.recording`.
#
# CONFIRMADO 2026-08-31 contra una URL real de producción: `data[:recording]` que manda Aircall en
# el call object NO es un endpoint de su API — es una URL de S3 pre-firmada
# (`...amazonaws.com/...?X-Amz-Algorithm=...&X-Amz-Signature=...`) que ya trae su propia
# autenticación en la query string. A diferencia de Twilio (Voice::Provider::Twilio::RecordingAttachmentService,
# cuyas URLs sí requieren Basic Auth con las credenciales del canal), mandarle Basic Auth extra a
# esta URL de S3 hace que S3 la rechace con 400 Bad Request — "solo un mecanismo de autenticación
# permitido" — por eso aquí NO se manda ningún header de auth, solo se sigue la URL tal cual.
class Crm::Aircall::RecordingAttachmentService
  ALLOWED_CONTENT_TYPE_PREFIXES = %w[audio/].freeze
  DEFAULT_FILENAME_EXTENSION = 'wav'.freeze

  def initialize(call:, recording_url:)
    @call = call
    @recording_url = recording_url
  end

  def perform
    return if recording_url.blank? || call.recording.attached?

    SafeFetch.fetch(recording_url, allowed_content_type_prefixes: ALLOWED_CONTENT_TYPE_PREFIXES) do |result|
      call.recording.attach(io: result.tempfile, filename: recording_filename(result), content_type: recording_content_type(result))
    end
  end

  private

  attr_reader :call, :recording_url

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
