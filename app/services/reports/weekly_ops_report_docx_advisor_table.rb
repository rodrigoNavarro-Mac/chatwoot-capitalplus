# Construcción del <w:tbl> OOXML del desglose por asesor, separado de
# Reports::WeeklyOpsReportDocxService solo para no pasar el límite de tamaño de clase — usa
# `escape` del servicio que lo incluye (mismo helper que el resto de las tablas/párrafos).
module Reports::WeeklyOpsReportDocxAdvisorTable
  ADVISOR_TABLE_HEADER = ['Asesor', 'Conversaciones', 'Tiempo 1er mensaje (min)', 'Tiempo de respuesta (min)'].freeze

  def advisor_table_xml(rows)
    header_row = advisor_table_row_xml(ADVISOR_TABLE_HEADER, header: true)
    body_rows = rows.map { |row| advisor_table_row_xml(row) }.join

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
        <w:tblGrid><w:gridCol/><w:gridCol/><w:gridCol/><w:gridCol/></w:tblGrid>
        #{header_row}
        #{body_rows}
      </w:tbl>
      <w:p/>
    XML
  end

  private

  def advisor_table_row_xml(cells, header: false)
    "<w:tr>#{cells.map { |value| advisor_table_cell_xml(value, header: header) }.join}</w:tr>"
  end

  def advisor_table_cell_xml(value, header: false)
    run_props = header ? '<w:rPr><w:b/></w:rPr>' : ''
    <<~XML
      <w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr>
        <w:p><w:r>#{run_props}<w:t xml:space="preserve">#{escape(value)}</w:t></w:r></w:p></w:tc>
    XML
  end
end
