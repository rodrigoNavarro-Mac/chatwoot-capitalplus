# Tablas/párrafos OOXML para las métricas de paridad con el reporte semanal viejo (deals creados,
# desglose entre semana/fin de semana, calidad por canal, distribución y conversión por asesor en
# Zoho, horario laboral) — separado de Reports::WeeklyOpsReportDocxTables solo por límite de
# tamaño de módulo; usa `heading_xml`/`paragraph_xml`/`simple_table_xml`/`insert_distribution_table`
# del servicio que lo incluye (Reports::WeeklyOpsReportDocxService).
module Reports::WeeklyOpsReportDocxTablesZoho
  ADVISOR_PERIOD_OF_WEEK_TABLE_HEADER = ['Asesor', '1er mensaje L-V (min)', '1er mensaje S-D (min)', 'Conversaciones L-V / S-D'].freeze
  CONTACT_TIME_BY_PERIOD_TABLE_HEADER = ['Periodo', 'Tiempo 1er mensaje (min)', 'Tiempo de respuesta (min)'].freeze
  QUALITY_BY_SOURCE_TABLE_HEADER = ['Fuente', 'Contactados', 'Total', '% Calidad'].freeze
  CONVERSION_BY_OWNER_TABLE_HEADER = %w[Asesor Contactados Descartados].freeze

  def insert_deals_created_line(sect_pr)
    text = deals_created_line_text(kpis)
    return if text.blank?

    sect_pr.add_previous_sibling(paragraph_xml(text))
  end

  def insert_advisor_period_of_week_table(sect_pr)
    rows = advisor_period_of_week_rows(kpis)
    return if rows.blank?

    sect_pr.add_previous_sibling(heading_xml('Desglose por asesor: entre semana vs fin de semana', size: 24))
    sect_pr.add_previous_sibling(simple_table_xml(ADVISOR_PERIOD_OF_WEEK_TABLE_HEADER, rows))
  end

  def insert_contact_time_by_period_table(sect_pr)
    rows = contact_time_by_period_rows(kpis)
    return if rows.blank?

    sect_pr.add_previous_sibling(heading_xml('Tiempos de contacto: entre semana vs fin de semana', size: 24))
    sect_pr.add_previous_sibling(simple_table_xml(CONTACT_TIME_BY_PERIOD_TABLE_HEADER, rows))
  end

  def insert_quality_by_source_table(sect_pr)
    rows = quality_by_source_rows(kpis)
    return if rows.blank?

    sect_pr.add_previous_sibling(heading_xml('Calidad de leads por canal', size: 24))
    sect_pr.add_previous_sibling(simple_table_xml(QUALITY_BY_SOURCE_TABLE_HEADER, rows))
  end

  def insert_owner_table(sect_pr)
    header = Reports::WeeklyOpsReportDocxTables::DISTRIBUTION_TABLE_HEADERS[:owner]
    insert_distribution_table(sect_pr, 'Distribución por asesor (Zoho)', header, owner_rows(kpis))
  end

  def insert_conversion_by_owner_table(sect_pr)
    rows = conversion_by_owner_rows(kpis)
    return if rows.blank?

    sect_pr.add_previous_sibling(heading_xml('Conversión y descarte por asesor', size: 24))
    sect_pr.add_previous_sibling(simple_table_xml(CONVERSION_BY_OWNER_TABLE_HEADER, rows))
  end

  def insert_schedule_distribution_line(sect_pr)
    text = schedule_distribution_line_text(kpis)
    return if text.blank?

    sect_pr.add_previous_sibling(paragraph_xml(text))
  end
end
