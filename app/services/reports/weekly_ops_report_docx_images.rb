# Inserción de imágenes (gráficas PNG en base64) en el .docx — separado de
# Reports::WeeklyOpsReportDocxService solo por límite de tamaño de clase. Decodifica el PNG,
# lo escribe en word/media/, registra la relación en document.xml.rels y arma el <w:drawing>
# OOXML que referencia esa relación.
module Reports::WeeklyOpsReportDocxImages
  IMAGE_REL_TYPE = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image'.freeze
  MAX_IMAGE_EMU_WIDTH = 5_400_000 # ~5.9in — cabe dentro de los márgenes usuales de un membrete A4/carta

  def insert_charts(sect_pr, rels_xml, zip_file)
    chart_images.each do |chart|
      title = chart[:title] || chart['title']
      sect_pr.add_previous_sibling(paragraph_xml(title)) if title.present?

      image_xml = image_paragraph_xml(chart, rels_xml, zip_file)
      sect_pr.add_previous_sibling(image_xml) if image_xml

      key = chart[:key] || chart['key']
      next if Reports::ReportCardAnalyses::DUAL_REPRESENTATION_CARD_KEYS.include?(key.to_s)

      insert_card_analysis_line(sect_pr, key)
    end
  end

  private

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
end
