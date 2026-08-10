# Construcción de <w:tbl> OOXML genéricas (N columnas, encabezado en negritas), separado de
# Reports::WeeklyOpsReportDocxService solo para no pasar el límite de tamaño de clase — usa
# `escape` del servicio que lo incluye (mismo helper que el resto de las tablas/párrafos).
module Reports::WeeklyOpsReportDocxTables
  ADVISOR_TABLE_HEADER = ['Asesor', 'Conversaciones', 'Tiempo 1er mensaje (min)', 'Tiempo de respuesta (min)'].freeze
  DISTRIBUTION_TABLE_HEADERS = {
    pipeline_status: %w[Estado Leads %],
    lead_source: %w[Fuente Leads %],
    discard_reason: %w[Motivo Leads %]
  }.freeze

  def insert_lead_source_table(sect_pr)
    rows = lead_source_rows(kpis)
    return if rows.blank?

    insert_distribution_table(sect_pr, 'Fuentes de prospectos', DISTRIBUTION_TABLE_HEADERS[:lead_source], rows)
    insert_quality_leads_line(sect_pr)
  end

  def insert_quality_leads_line(sect_pr)
    zoho_leads = kpis[:zoho_leads] || {}
    count = zoho_leads[:quality_leads_count]
    return if count.nil?

    sect_pr.add_previous_sibling(paragraph_xml("Leads de calidad: #{count} (#{zoho_leads[:quality_leads_percent]}%)"))
  end

  def insert_distribution_table(sect_pr, title, header, rows)
    return if rows.blank?

    sect_pr.add_previous_sibling(heading_xml(title, size: 24))
    sect_pr.add_previous_sibling(simple_table_xml(header, rows))
  end

  def simple_table_xml(header, rows)
    header_row = table_row_xml_cells(header, header: true)
    body_rows = rows.map { |row| table_row_xml_cells(row) }.join
    grid_cols = '<w:gridCol/>' * header.size

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
        <w:tblGrid>#{grid_cols}</w:tblGrid>
        #{header_row}
        #{body_rows}
      </w:tbl>
      <w:p/>
    XML
  end

  private

  def table_row_xml_cells(cells, header: false)
    "<w:tr>#{cells.map { |value| table_cell_xml(value, header: header) }.join}</w:tr>"
  end

  def table_cell_xml(value, header: false)
    run_props = header ? '<w:rPr><w:b/></w:rPr>' : ''
    <<~XML
      <w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr>
        <w:p><w:r>#{run_props}<w:t xml:space="preserve">#{escape(value)}</w:t></w:r></w:p></w:tc>
    XML
  end
end
