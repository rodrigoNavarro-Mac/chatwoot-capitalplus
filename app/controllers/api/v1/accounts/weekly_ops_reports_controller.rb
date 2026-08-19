class Api::V1::Accounts::WeeklyOpsReportsController < Api::V1::Accounts::BaseController
  include DateRangeHelper

  before_action :fetch_inbox
  before_action :check_authorization
  before_action :fetch_weekly_ops_report, only: [:show, :pdf]

  def index
    @weekly_ops_reports = @inbox.weekly_ops_reports.recent_first.limit(26)
  end

  def show; end

  # Deja el registro en "pending" y encola la generación real (kpis + LLM) en segundo plano — ver
  # Reports::GenerateOnDemandWeeklyOpsReportJob para el porqué: armar los KPIs y pedirle al LLM el
  # análisis ejecutivo Y el mini-análisis de las 15 cards puede tardar más de los 15s del timeout
  # de Rack::Timeout. El frontend hace polling a #show hasta que status deje de ser "pending".
  def create
    @weekly_ops_report = pending_report!
    Reports::GenerateOnDemandWeeklyOpsReportJob.perform_later(@weekly_ops_report.id, report_params)
    render :show
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def pdf
    send_data pdf_bytes,
              filename: "reporte-semanal-#{@inbox.name.parameterize}-#{@weekly_ops_report.period_start}.pdf",
              type: 'application/pdf',
              disposition: 'attachment'
  rescue Reports::DocxToPdfConverterService::ConversionError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # Si el desarrollo tiene un .docx con membrete configurado, se arma el reporte en ese template
  # (preservando header/footer) y se convierte a PDF con Gotenberg; si no, se usa el PDF genérico
  # armado con Prawn.
  def pdf_bytes
    branding = @inbox.report_branding

    if branding&.letterhead_template&.attached?
      docx_io = Reports::WeeklyOpsReportDocxService.new(
        weekly_ops_report: @weekly_ops_report,
        branding: branding,
        chart_images: chart_images_params
      ).generate
      Reports::DocxToPdfConverterService.new(docx_io).convert
    else
      Reports::WeeklyOpsReportPdfService.new(
        weekly_ops_report: @weekly_ops_report,
        branding: branding,
        chart_images: chart_images_params
      ).generate.read
    end
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def fetch_weekly_ops_report
    @weekly_ops_report = @inbox.weekly_ops_reports.find(params[:id])
  end

  def check_authorization
    authorize(WeeklyOpsReport)
  end

  # period_start/period_end se calculan igual que V2::Reports::WeeklyOpsReportBuilder#date_bounds
  # (mismo DateRangeHelper#range), pero sin construir los KPIs todavía — eso lo hace el job.
  def pending_report!
    period_type = params[:period_type].presence || 'week'
    record = @inbox.weekly_ops_reports.find_or_initialize_by(period_start: range.begin.to_date, period_type: period_type)
    record.assign_attributes(
      account: Current.account,
      period_end: (range.end - 1.second).to_date,
      status: 'pending',
      generated_by: Current.user
    )
    record.save!
    record
  end

  def report_params
    { since: params[:since], until: params[:until], period_type: params[:period_type].presence || 'week' }
  end

  def chart_images_params
    Array(params[:chart_images]).map { |chart| { title: chart[:title], data_url: chart[:data_url], key: chart[:key] } }
  end
end
