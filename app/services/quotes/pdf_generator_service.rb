# Convierte el HTML ya renderizado (Quotes::HtmlRendererService) a PDF llamando a Gotenberg —
# mismo servicio Docker que ya usa Reports::DocxToPdfConverterService, pero contra su ruta de
# Chromium en vez de LibreOffice, ya que aquí partimos de una plantilla HTML/CSS diseñada a mano
# (no de un .docx con membrete).
#
# Usa `multipart-post` (Net::HTTP::Post::Multipart) en vez de HTTParty: HTTParty#multipart
# confirmado roto en este entorno (Gotenberg responde 500 "malformed MIME header") en cuanto el
# body combina el archivo con más de un campo adicional — DocxToPdfConverterService no lo nota
# porque solo manda el archivo solo. multipart-post ya es una dependencia transitiva del bundle
# (usada por faraday) y genera el multipart correctamente (confirmado contra Gotenberg real).
require 'net/http/post/multipart'

class Quotes::PdfGeneratorService
  class ConversionError < StandardError; end

  CONVERT_PATH = '/forms/chromium/convert/html'.freeze

  # La plantilla ya está diseñada a tamaño A4 (794x1123px ~ 96dpi) en una sola página — sin fijar
  # el tamaño de papel/márgenes, Gotenberg usa su default (Letter con márgenes de ~1in) y el
  # contenido se corta en una segunda página.
  # Alto ligeramente mayor a A4 (11.7in) a propósito: el contenido real (con el texto legal y las
  # 12 filas de la tabla) desborda por un par de px el alto exacto de 1123px del diseño, lo que
  # sin este margen extra deja una fila suelta en una segunda página en blanco.
  PAPER_WIDTH_INCHES = '8.27'.freeze
  PAPER_HEIGHT_INCHES = '12.0'.freeze

  def initialize(html)
    @html = html
  end

  def generate
    with_tempfile do |file|
      response = post(file)

      raise ConversionError, "Gotenberg respondió #{response.code}: #{response.body}" unless response.code == '200'

      response.body
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
    raise ConversionError, "No se pudo conectar con Gotenberg: #{e.message}"
  end

  private

  attr_reader :html

  def post(file)
    uri = URI.parse("#{gotenberg_url}#{CONVERT_PATH}")
    io = UploadIO.new(file, 'text/html', 'index.html')
    request = Net::HTTP::Post::Multipart.new(
      uri.path,
      'files' => io,
      'paperWidth' => PAPER_WIDTH_INCHES,
      'paperHeight' => PAPER_HEIGHT_INCHES,
      'marginTop' => '0', 'marginBottom' => '0', 'marginLeft' => '0', 'marginRight' => '0',
      'printBackground' => 'true'
    )

    Net::HTTP.start(uri.host, uri.port, read_timeout: 30, open_timeout: 10) { |http| http.request(request) }
  end

  # Gotenberg identifica el punto de entrada de la ruta de Chromium por nombre de archivo literal
  # ("index.html"), a diferencia de la ruta de LibreOffice donde solo importa la extensión.
  def with_tempfile(&)
    dir = Dir.mktmpdir
    path = File.join(dir, 'index.html')
    File.write(path, html)

    File.open(path, 'rb', &)
  ensure
    FileUtils.remove_entry(dir) if dir
  end

  def gotenberg_url
    ENV.fetch('GOTENBERG_URL')
  end
end
