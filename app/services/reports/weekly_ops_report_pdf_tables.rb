# Tablas/líneas del PDF para las métricas de paridad con el reporte semanal viejo (deals creados,
# desglose entre semana/fin de semana, calidad por canal, distribución y conversión por asesor en
# Zoho, horario laboral) — separado de Reports::WeeklyOpsReportPdfService solo por límite de
# tamaño de clase; usa `accent_color`/`render_distribution_table` del servicio que lo incluye.
module Reports::WeeklyOpsReportPdfTables
  def render_deals_created_line(pdf)
    text = deals_created_line_text(kpis)
    return if text.blank?

    pdf.font_size(10) { pdf.text(text) }
    pdf.move_down(10)
  end

  def render_advisor_period_of_week_table(pdf)
    rows = advisor_period_of_week_rows(kpis)
    return if rows.blank?

    header = ['Asesor', '1er mensaje L-V (min)', '1er mensaje S-D (min)', 'Conversaciones L-V / S-D']
    render_pdf_table(pdf, 'Desglose por asesor: entre semana vs fin de semana', header, rows)
  end

  def render_contact_time_by_period_table(pdf)
    rows = contact_time_by_period_rows(kpis)
    return if rows.blank?

    header = ['Periodo', 'Tiempo 1er mensaje (min)', 'Tiempo de respuesta (min)']
    render_pdf_table(pdf, 'Tiempos de contacto: entre semana vs fin de semana', header, rows)
  end

  def render_quality_by_source_table(pdf)
    rows = quality_by_source_rows(kpis)
    return if rows.blank?

    render_pdf_table(pdf, 'Calidad de leads por canal', ['Fuente', 'Contactados', 'Total', '% Calidad'], rows)
  end

  def render_owner_table(pdf)
    render_distribution_table(pdf, 'Distribución por asesor (Zoho)', %w[Asesor Leads %], owner_rows(kpis))
  end

  def render_conversion_by_owner_table(pdf)
    rows = conversion_by_owner_rows(kpis)
    return if rows.blank?

    render_pdf_table(pdf, 'Conversión y descarte por asesor', %w[Asesor Convertidos Descartados], rows)
  end

  def render_schedule_distribution_line(pdf)
    text = schedule_distribution_line_text(kpis)
    return if text.blank?

    pdf.font_size(10) { pdf.text(text) }
    pdf.move_down(15)
  end

  private

  def render_pdf_table(pdf, title, header, rows)
    pdf.font_size(14) { pdf.text(title, style: :bold) }
    pdf.move_down(6)

    pdf.table([header] + rows, header: true, width: pdf.bounds.width) do |t|
      t.row(0).font_style = :bold
      t.row(0).background_color = accent_color
    end
    pdf.move_down(15)
  end
end
