# Convierte un .docx a PDF llamando a Gotenberg (LibreOffice headless por dentro), preservando el
# membrete/header/footer del Word exactamente como se ve en Word — a diferencia de Pandoc/LaTeX,
# que reformatea el documento y pierde ese diseño.
class Reports::DocxToPdfConverterService
  class ConversionError < StandardError; end

  CONVERT_PATH = '/forms/libreoffice/convert'.freeze

  def initialize(docx_io)
    @docx_io = docx_io
  end

  def convert
    with_tempfile do |file|
      response = HTTParty.post(
        "#{gotenberg_url}#{CONVERT_PATH}",
        body: { files: file },
        multipart: true,
        timeout: 30
      )

      raise ConversionError, "Gotenberg respondió #{response.code}: #{response.body}" unless response.code == 200

      response.body
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
    raise ConversionError, "No se pudo conectar con Gotenberg: #{e.message}"
  end

  private

  attr_reader :docx_io

  # HTTParty solo arma un part multipart de archivo real cuando el valor responde a #path (File/
  # Tempfile) — un StringIO envuelto en UploadIO no lo serializa como archivo. Gotenberg además
  # identifica el tipo por la extensión del nombre del archivo, así que el Tempfile debe terminar
  # en ".docx".
  def with_tempfile
    docx_io.rewind if docx_io.respond_to?(:rewind)

    file = Tempfile.new(['weekly_ops_report', '.docx'])
    file.binmode
    file.write(docx_io.read)
    file.rewind

    yield file
  ensure
    file&.close
    file&.unlink
  end

  def gotenberg_url
    ENV.fetch('GOTENBERG_URL')
  end
end
