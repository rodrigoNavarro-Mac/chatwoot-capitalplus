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
  include Reports::ReportSummaryRowsZoho
  include Reports::ReportSummaryRowsPeriodOfWeek
  include Reports::WeeklyOpsReportDocxTables
  include Reports::WeeklyOpsReportDocxTablesZoho
  include Reports::WeeklyOpsReportDocxImages
  include Reports::ReportCardAnalyses

  W_XMLNS = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'.freeze

  # chart_images: Array<{ key: String, title: String, data_url: String }>, en el mismo orden que
  # las cards en pantalla (ver WeeklyOpsReport.vue).
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
    insert_header(sect_pr)
    insert_analysis(sect_pr)
    insert_summary(sect_pr)
    insert_charts(sect_pr, rels_xml, zip_file)

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

  def insert_header(sect_pr)
    sect_pr.add_previous_sibling(heading_xml("Reporte semanal — #{kpis[:inbox_name]}"))
    sect_pr.add_previous_sibling(paragraph_xml("Periodo: #{format_period}"))
  end

  def insert_summary(sect_pr)
    sect_pr.add_previous_sibling(summary_table_xml)
    insert_deals_created_line(sect_pr)
    insert_deals_activity_line(sect_pr)
    insert_tables(sect_pr)
  end

  # Mismo orden que las cards en WeeklyOpsReport.vue (ver comentario de clase ahí).
  def insert_tables(sect_pr)
    insert_distribution_table_with_analysis(sect_pr, 'Embudo de ventas', DISTRIBUTION_TABLE_HEADERS[:funnel], funnel_rows(kpis), :pipeline)
    insert_pipeline_status_tables(sect_pr)
    insert_contact_time_by_period_table(sect_pr)
    insert_advisor_period_of_week_table(sect_pr)
    insert_by_advisor_table(sect_pr)
    insert_conversion_totals_line(sect_pr)
    insert_lead_source_table(sect_pr)
    insert_quality_by_source_table(sect_pr)
    insert_owner_table(sect_pr)
    insert_distribution_table_with_analysis(
      sect_pr, 'Motivos de descarte', DISTRIBUTION_TABLE_HEADERS[:discard_reason], discard_reason_rows(kpis), :discard_reasons
    )
    insert_schedule_distribution_line(sect_pr)
    insert_calls_table(sect_pr)
  end

  def insert_distribution_table_with_analysis(sect_pr, title, header, rows, key)
    return if rows.blank?

    insert_distribution_table(sect_pr, title, header, rows)
    insert_card_analysis_line(sect_pr, key)
  end

  # Dos tablas (nuevos / seguimiento) bajo la misma card de análisis — ver
  # V2::Reports::ZohoLeadsMetrics#summary para el porqué de la separación.
  def insert_pipeline_status_tables(sect_pr)
    new_rows = pipeline_status_new_rows(kpis)
    follow_up_rows = pipeline_status_follow_up_rows(kpis)
    return if new_rows.blank? && follow_up_rows.blank?

    insert_distribution_table(sect_pr, 'Distribución del pipeline — leads nuevos', DISTRIBUTION_TABLE_HEADERS[:pipeline_status], new_rows)
    insert_distribution_table(sect_pr, 'Distribución del pipeline — seguimiento', DISTRIBUTION_TABLE_HEADERS[:pipeline_status], follow_up_rows)
    insert_card_analysis_line(sect_pr, :zoho_pipeline_status)
  end

  def insert_by_advisor_table(sect_pr)
    rows = advisor_rows(kpis)
    return if rows.blank?

    sect_pr.add_previous_sibling(heading_xml('Desglose por asesor', size: 24))
    sect_pr.add_previous_sibling(simple_table_xml(ADVISOR_TABLE_HEADER, rows))
    insert_card_analysis_line(sect_pr, :by_advisor)
  end

  def insert_analysis(sect_pr)
    return if report.llm_analysis.blank?

    sect_pr.add_previous_sibling(heading_xml('Análisis', size: 24))
    report.llm_analysis.to_s.split("\n").each do |line|
      sect_pr.add_previous_sibling(paragraph_xml(line))
    end
  end

  # Nota corta en cursiva bajo la tabla/gráfica de una card — ver Reports::ReportCardAnalyses.
  def insert_card_analysis_line(sect_pr, key)
    text = card_analysis(key)
    return if text.blank?

    sect_pr.add_previous_sibling(italic_paragraph_xml(text))
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

  def italic_paragraph_xml(text)
    <<~XML
      <w:p><w:r><w:rPr><w:i/><w:color w:val="555555"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr>
        <w:t xml:space="preserve">#{escape(text)}</w:t></w:r></w:p>
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

  def escape(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end
end
