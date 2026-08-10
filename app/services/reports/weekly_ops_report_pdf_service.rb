require 'prawn'
require 'prawn/table'

# Arma el PDF exportable del reporte semanal operativo: encabezado con el branding del inbox
# (accent_color/logo, Reports::InboxBranding), tabla resumen de KPIs, las gráficas que el
# frontend ya renderizó con Chart.js (recibidas como PNG en data URL, mismo patrón de
# AgentBots::MaintenanceReportService para insertar imágenes con Prawn) y el análisis del LLM.
class Reports::WeeklyOpsReportPdfService
  include Reports::ReportSummaryRows

  MAX_IMAGE_WIDTH = 500
  MAX_IMAGE_HEIGHT = 260

  # chart_images: Array<{ title: String, data_url: String }> — PNG en base64 (chart.toBase64Image()).
  def initialize(weekly_ops_report:, branding: nil, chart_images: [])
    @report = weekly_ops_report
    @branding = branding
    @chart_images = chart_images
  end

  def generate
    pdf = Prawn::Document.new(page_size: 'A4', margin: [40, 50, 40, 50])

    render_header(pdf)
    render_summary_table(pdf)
    render_by_advisor_table(pdf)
    render_charts(pdf)
    render_analysis(pdf)

    io = StringIO.new(pdf.render)
    io.rewind
    io
  end

  private

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
  end

  def render_charts(pdf)
    return if chart_images.blank?

    pdf.font_size(14) { pdf.text('Gráficas', style: :bold) }
    pdf.move_down(6)

    chart_images.each do |chart|
      pdf.font_size(10) { pdf.text(chart[:title].to_s) } if chart[:title].present?
      add_chart_image(pdf, chart[:data_url])
      pdf.move_down(10)
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
  end
end
