require 'zip'

# Abre la plantilla .docx con membrete (Reports::InboxBranding#letterhead_template — header/footer/
# márgenes ya diseñados en Word) e inserta el contenido del reporte semanal en el cuerpo, justo
# antes del <w:sectPr> final, que es exactamente donde python-docx (Document#add_paragraph, etc.)
# agrega contenido nuevo — así el membrete queda intacto.
#
# No se usa ninguna gema de "docx templating": se manipula el OOXML directo (el .docx es un .zip
# con XML adentro) porque la gema `docx` de Ruby no tiene API para insertar tablas o imágenes
# nuevas, solo lectura y reemplazo de texto.
class Reports::WeeklyOpsReportDocxService
  include Reports::ReportSummaryRows
  include Reports::WeeklyOpsReportDocxTables

  W_XMLNS = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'.freeze
  IMAGE_REL_TYPE = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image'.freeze
  MAX_IMAGE_EMU_WIDTH = 5_400_000 # ~5.9in — cabe dentro de los márgenes usuales de un membrete A4/carta

  def initialize(weekly_ops_report:, branding:, chart_images: [])
    @report = weekly_ops_report
    @branding = branding
    @chart_images = chart_images
  end

  def generate
    zip_file = Zip::File.open_buffer(StringIO.new(branding.letterhead_template.download))

    document_xml = Nokogiri::XML(zip_file.read('word/document.xml'))
    rels_xml = Nokogiri::XML(zip_file.read('word/_rels/document.xml.rels'))

    sect_pr = section_properties(document_xml)
    insert_summary(sect_pr)
    insert_charts(sect_pr, rels_xml, zip_file)
    insert_analysis(sect_pr)

    zip_file.get_output_stream('word/document.xml') { |f| f.write(document_xml.to_xml) }
    zip_file.get_output_stream('word/_rels/document.xml.rels') { |f| f.write(rels_xml.to_xml) }

    output = StringIO.new
    zip_file.write_buffer(output)
    output.rewind
    output
  end

  private

  attr_reader :report, :branding, :chart_images

  def kpis
    @kpis ||= report.kpis.with_indifferent_access
  end

  def section_properties(document_xml)
    body = document_xml.at_xpath('//w:body', 'w' => W_XMLNS)
    body.at_xpath('w:sectPr', 'w' => W_XMLNS) || body.add_child('<w:sectPr/>')
  end

  def insert_summary(sect_pr)
    sect_pr.add_previous_sibling(heading_xml("Reporte semanal — #{kpis[:inbox_name]}"))
    sect_pr.add_previous_sibling(paragraph_xml("Periodo: #{format_period}"))
    sect_pr.add_previous_sibling(summary_table_xml)
    insert_by_advisor_table(sect_pr)
    insert_calls_table(sect_pr)
    insert_distribution_table(sect_pr, 'Distribución del pipeline', DISTRIBUTION_TABLE_HEADERS[:pipeline_status], pipeline_status_rows(kpis))
    insert_lead_source_table(sect_pr)
    insert_distribution_table(sect_pr, 'Motivos de descarte', DISTRIBUTION_TABLE_HEADERS[:discard_reason], discard_reason_rows(kpis))
  end

  def insert_by_advisor_table(sect_pr)
    rows = advisor_rows(kpis)
    return if rows.blank?

    sect_pr.add_previous_sibling(heading_xml('Desglose por asesor', size: 24))
    sect_pr.add_previous_sibling(simple_table_xml(ADVISOR_TABLE_HEADER, rows))
  end

  def insert_charts(sect_pr, rels_xml, zip_file)
    chart_images.each do |chart|
      image_xml = image_paragraph_xml(chart, rels_xml, zip_file)
      sect_pr.add_previous_sibling(image_xml) if image_xml
    end
  end

  def insert_analysis(sect_pr)
    return if report.llm_analysis.blank?

    sect_pr.add_previous_sibling(heading_xml('Análisis', size: 24))
    report.llm_analysis.to_s.split("\n").each do |line|
      sect_pr.add_previous_sibling(paragraph_xml(line))
    end
  end

  def format_period
    period = kpis[:period] || {}
    "#{period[:since]} — #{period[:until]}"
  end

  # ── Construcción de XML (fragments insertados vía Nokogiri#add_previous_sibling, que resuelve
  # los namespaces heredados de <w:document> — no hace falta declarar xmlns:w en cada fragmento) ──

  def heading_xml(text, size: 32)
    <<~XML
      <w:p><w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr>
        <w:r><w:rPr><w:b/><w:sz w:val="#{size}"/><w:szCs w:val="#{size}"/></w:rPr>
        <w:t xml:space="preserve">#{escape(text)}</w:t></w:r></w:p>
    XML
  end

  def paragraph_xml(text)
    <<~XML
      <w:p><w:r><w:t xml:space="preserve">#{escape(text)}</w:t></w:r></w:p>
    XML
  end

  def summary_table_xml
    rows = summary_rows(kpis).map { |label, value| table_row_xml(label, value) }.join

    <<~XML
      <w:tbl>
        <w:tblPr><w:tblW w:w="0" w:type="auto"/>
          <w:tblBorders>
            <w:top w:val="single" w:sz="4" w:color="auto"/>
            <w:left w:val="single" w:sz="4" w:color="auto"/>
            <w:bottom w:val="single" w:sz="4" w:color="auto"/>
            <w:right w:val="single" w:sz="4" w:color="auto"/>
            <w:insideH w:val="single" w:sz="4" w:color="auto"/>
            <w:insideV w:val="single" w:sz="4" w:color="auto"/>
          </w:tblBorders>
        </w:tblPr>
        <w:tblGrid><w:gridCol/><w:gridCol/></w:tblGrid>
        #{rows}
      </w:tbl>
      <w:p/>
    XML
  end

  def table_row_xml(label, value)
    <<~XML
      <w:tr>
        <w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr><w:p><w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">#{escape(label)}</w:t></w:r></w:p></w:tc>
        <w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr><w:p><w:r><w:t xml:space="preserve">#{escape(value)}</w:t></w:r></w:p></w:tc>
      </w:tr>
    XML
  end

  # ── Imagen embebida (gráfica) ──────────────────────────────────────────────

  def image_paragraph_xml(chart, rels_xml, zip_file)
    width, height, image_bytes = decode_chart_image(chart)
    return nil unless width&.positive? && height&.positive?

    media_name = "image_chart_#{SecureRandom.hex(4)}.png"
    zip_file.get_output_stream("word/media/#{media_name}") { |f| f.write(image_bytes) }
    rel_id = add_image_relationship(rels_xml, media_name)

    drawing_xml(rel_id, *scaled_emu_size(width, height))
  end

  def decode_chart_image(chart)
    data_url = chart[:data_url] || chart['data_url']
    return [nil, nil, nil] if data_url.blank?

    _, encoded = data_url.split(',', 2)
    return [nil, nil, nil] if encoded.blank?

    image_bytes = Base64.decode64(encoded)
    width, height = png_dimensions(image_bytes)
    [width, height, image_bytes]
  end

  def scaled_emu_size(width, height)
    emu_width = MAX_IMAGE_EMU_WIDTH
    emu_height = (emu_width.to_f * height / width).round
    [emu_width, emu_height]
  end

  # rubocop:disable Metrics/MethodLength -- plantilla OOXML literal, no lógica real
  def drawing_xml(rel_id, emu_width, emu_height)
    doc_pr_id = rand(1000..999_999)

    <<~XML
      <w:p><w:r><w:drawing>
        <wp:inline distT="0" distB="0" distL="0" distR="0" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">
          <wp:extent cx="#{emu_width}" cy="#{emu_height}"/>
          <wp:docPr id="#{doc_pr_id}" name="Chart#{doc_pr_id}"/>
          <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
            <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
              <pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
                <pic:nvPicPr><pic:cNvPr id="#{doc_pr_id}" name="Chart#{doc_pr_id}"/><pic:cNvPicPr/></pic:nvPicPr>
                <pic:blipFill>
                  <a:blip r:embed="#{rel_id}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>
                  <a:stretch><a:fillRect/></a:stretch>
                </pic:blipFill>
                <pic:spPr>
                  <a:xfrm><a:off x="0" y="0"/><a:ext cx="#{emu_width}" cy="#{emu_height}"/></a:xfrm>
                  <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                </pic:spPr>
              </pic:pic>
            </a:graphicData>
          </a:graphic>
        </wp:inline>
      </w:drawing></w:r></w:p>
    XML
  end
  # rubocop:enable Metrics/MethodLength

  def add_image_relationship(rels_xml, media_name)
    rel_id = "rId#{next_relationship_numeric_id(rels_xml)}"
    relationships = rels_xml.at_xpath('//xmlns:Relationships', 'xmlns' => 'http://schemas.openxmlformats.org/package/2006/relationships')
    relationships.add_child(%(<Relationship Id="#{rel_id}" Type="#{IMAGE_REL_TYPE}" Target="media/#{media_name}"/>))
    rel_id
  end

  def next_relationship_numeric_id(rels_xml)
    existing_ids = rels_xml.xpath('//xmlns:Relationship/@Id', 'xmlns' => 'http://schemas.openxmlformats.org/package/2006/relationships')
                           .map { |id| id.value.delete_prefix('rId').to_i }
    (existing_ids.max || 0) + 1
  end

  # Lee ancho/alto directo del chunk IHDR del PNG (bytes 16..23) — evita depender de una gema de
  # imágenes solo para esto; los PNG que manda el frontend (canvas.toBase64Image()) siempre traen
  # ese chunk en esa posición fija.
  def png_dimensions(bytes)
    return [nil, nil] if bytes.nil? || bytes.bytesize < 24

    bytes.byteslice(16, 8).unpack('N2')
  end

  def escape(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end
end
