require 'prawn'
require 'prawn/table'

# Arma el PDF exportable del reporte semanal operativo: encabezado con el branding del inbox
# (accent_color/logo, Reports::InboxBranding), tabla resumen de KPIs, las gráficas que el
# frontend ya renderizó con Chart.js (recibidas como PNG en data URL, mismo patrón de
# AgentBots::MaintenanceReportService para insertar imágenes con Prawn) y el análisis del LLM.
class Reports::WeeklyOpsReportPdfService
  include Reports::ReportSummaryRows
  include Reports::ReportSummaryRowsZoho
  include Reports::ReportSummaryRowsPeriodOfWeek
  include Reports::WeeklyOpsReportPdfTables
  include Reports::ReportCardAnalyses

  MAX_IMAGE_WIDTH = 500
  MAX_IMAGE_HEIGHT = 260

  # chart_images: Array<{ key: String, title: String, data_url: String }> — PNG en base64
  # (chart.toBase64Image()), en el mismo orden que las cards en pantalla (ver WeeklyOpsReport.vue).
  def initialize(weekly_ops_report:, branding: nil, chart_images: [])
    @report = weekly_ops_report
    @branding = branding
    @chart_images = chart_images
  end

  def generate
    pdf = Prawn::Document.new(page_size: 'A4', margin: [40, 50, 40, 50])

    render_header(pdf)
    render_summary_table(pdf)
    render_deals_created_line(pdf)
    render_analysis(pdf)
    render_tables(pdf)
    render_charts(pdf)

    io = StringIO.new(pdf.render)
    io.rewind
    io
  end

  private

  # Mismo orden que las cards en WeeklyOpsReport.vue (ver comentario de clase ahí) — el resumen
  # general, deals creados y el análisis ejecutivo ya se renderizaron antes de llamar a este método.
  def render_tables(pdf)
    render_funnel_table(pdf)
    render_pipeline_status_tables(pdf)
    render_contact_time_by_period_table(pdf)
    render_advisor_period_of_week_table(pdf)
    render_by_advisor_table(pdf)
    render_conversion_totals_line(pdf)
    render_lead_source_table(pdf)
    render_quality_by_source_table(pdf)
    render_owner_table(pdf)
    render_discard_reasons_table(pdf)
    render_schedule_distribution_line(pdf)
    render_calls_table(pdf)
  end

  attr_reader :report, :branding, :chart_images

  def kpis
    @kpis ||= report.kpis.with_indifferent_access
  end

  def accent_color
    @accent_color ||= (branding&.accent_color_or_default || Reports::InboxBranding::DEFAULT_ACCENT_COLOR).delete('#')
  end

  def render_header(pdf)
    add_logo(pdf) if branding&.logo&.attached?

    pdf.fill_color accent_color
    pdf.font_size(20) { pdf.text("Reporte semanal — #{kpis[:inbox_name]}", style: :bold) }
    pdf.fill_color '000000'
    pdf.move_down(4)
    pdf.font_size(11) { pdf.text("Periodo: #{format_period}") }
    pdf.move_down(10)
    pdf.stroke_color accent_color
    pdf.stroke_horizontal_rule
    pdf.stroke_color '000000'
    pdf.move_down(15)
  end

  def add_logo(pdf)
    pdf.image StringIO.new(branding.logo.download), fit: [120, 60], position: :right
    pdf.move_down(4)
  rescue StandardError => e
    Rails.logger.warn("[WeeklyOpsReportPdf] skip logo: #{e.message}")
  end

  def format_period
    period = kpis[:period] || {}
    "#{period[:since]} — #{period[:until]}"
  end

  def render_summary_table(pdf)
    pdf.font_size(14) { pdf.text('Resumen', style: :bold) }
    pdf.move_down(6)

    rows = [%w[Métrica Valor]] + summary_rows(kpis)
    pdf.table(rows, header: true, width: pdf.bounds.width) do |t|
      t.row(0).font_style = :bold
      t.row(0).background_color = accent_color
    end
    pdf.move_down(15)
  end

  def render_by_advisor_table(pdf)
    rows = advisor_rows(kpis)
    return if rows.blank?

    pdf.font_size(14) { pdf.text('Desglose por asesor', style: :bold) }
    pdf.move_down(6)

    header = ['Asesor', 'Conversaciones', 'Tiempo 1er mensaje (min)', 'Tiempo de respuesta (min)']
    pdf.table([header] + rows, header: true, width: pdf.bounds.width) do |t|
      t.row(0).font_style = :bold
      t.row(0).background_color = accent_color
    end
    pdf.move_down(15)
    render_card_analysis_line(pdf, :by_advisor)
  end

  def render_calls_table(pdf)
    rows = call_advisor_rows(kpis)
    return if rows.blank?

    pdf.font_size(14) { pdf.text('Llamadas por asesor (Aircall)', style: :bold) }
    pdf.move_down(6)

    header = ['Asesor', 'Llamadas', '% Contestadas', 'Duración promedio']
    pdf.table([header] + rows, header: true, width: pdf.bounds.width) do |t|
      t.row(0).font_style = :bold
      t.row(0).background_color = accent_color
    end
    pdf.move_down(15)
    render_calls_summary_line(pdf)
    render_card_analysis_line(pdf, :aircall_calls)
  end

  def render_calls_summary_line(pdf)
    text = call_summary_line_text(kpis)
    return if text.blank?

    pdf.font_size(10) { pdf.text(text) }
    pdf.move_down(15)
  end

  def render_funnel_table(pdf)
    rows = funnel_rows(kpis)
    return if rows.blank?

    render_distribution_table(pdf, 'Embudo de ventas', ['Etapa', 'Cantidad', '% real', '% meta', 'Diferencia'], rows)
    render_card_analysis_line(pdf, :pipeline)
  end

  def render_lead_source_table(pdf)
    rows = lead_source_rows(kpis)
    return if rows.blank?

    render_distribution_table(pdf, 'Fuentes de prospectos', %w[Fuente Leads %], rows)
    render_quality_leads_line(pdf)
    render_card_analysis_line(pdf, :zoho_source)
  end

  def render_quality_leads_line(pdf)
    zoho_leads = kpis[:zoho_leads] || {}
    count = zoho_leads[:quality_leads_count]
    return if count.nil?

    pdf.font_size(10) { pdf.text("Leads de calidad: #{count} (#{zoho_leads[:quality_leads_percent]}%)") }
    pdf.move_down(15)
  end

  def render_discard_reasons_table(pdf)
    rows = discard_reason_rows(kpis)
    return if rows.blank?

    render_distribution_table(pdf, 'Motivos de descarte', %w[Motivo Leads %], rows)
    render_card_analysis_line(pdf, :discard_reasons)
  end

  def render_distribution_table(pdf, title, header, rows)
    return if rows.blank?

    pdf.font_size(14) { pdf.text(title, style: :bold) }
    pdf.move_down(6)

    pdf.table([header] + rows, header: true, width: pdf.bounds.width) do |t|
      t.row(0).font_style = :bold
      t.row(0).background_color = accent_color
    end
    pdf.move_down(15)
  end

  def render_charts(pdf)
    return if chart_images.blank?

    pdf.font_size(14) { pdf.text('Gráficas', style: :bold) }
    pdf.move_down(6)

    chart_images.each do |chart|
      pdf.font_size(10) { pdf.text(chart[:title].to_s) } if chart[:title].present?
      add_chart_image(pdf, chart[:data_url])
      pdf.move_down(6)
      render_card_analysis_line(pdf, chart[:key])
      pdf.move_down(4)
    end
  end

  def add_chart_image(pdf, data_url)
    return if data_url.blank?

    _, encoded = data_url.split(',', 2)
    return if encoded.blank?

    pdf.image StringIO.new(Base64.decode64(encoded)), fit: [MAX_IMAGE_WIDTH, MAX_IMAGE_HEIGHT]
  rescue StandardError => e
    Rails.logger.warn("[WeeklyOpsReportPdf] skip chart image: #{e.message}")
  end

  def render_analysis(pdf)
    return if report.llm_analysis.blank?

    pdf.font_size(14) { pdf.text('Análisis', style: :bold) }
    pdf.move_down(6)
    pdf.font_size(11) { pdf.text(report.llm_analysis) }
    pdf.move_down(15)
  end

  # Nota corta en cursiva bajo la tabla/gráfica de una card — ver Reports::ReportCardAnalyses.
  def render_card_analysis_line(pdf, key)
    text = card_analysis(key)
    return if text.blank?

    pdf.fill_color '555555'
    pdf.font_size(9) { pdf.text(text, style: :italic) }
    pdf.fill_color '000000'
    pdf.move_down(8)
  end
end
