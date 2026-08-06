class Api::V1::Accounts::WeeklyOpsReportsController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :check_authorization
  before_action :fetch_weekly_ops_report, only: [:show, :pdf]

  def index
    @weekly_ops_reports = @inbox.weekly_ops_reports.recent_first.limit(26)
  end

  def show; end

  def create
    @weekly_ops_report = generate_report!
    render :show
  rescue ActiveRecord::RecordInvalid, RubyLLM::Error => e
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

  def generate_report!
    kpis = V2::Reports::WeeklyOpsReportBuilder.new(
      account: Current.account,
      inbox: @inbox,
      params: { since: params[:since], until: params[:until] }
    ).build
    analysis = Reports::WeeklyOpsAnalysisLlmService.new(account: Current.account, kpis: kpis).generate

    period = kpis[:period] || {}
    record = @inbox.weekly_ops_reports.find_or_initialize_by(period_start: period[:since])
    record.assign_attributes(
      account: Current.account,
      period_end: period[:until],
      kpis: kpis,
      llm_analysis: analysis,
      status: 'completed',
      generated_by: Current.user
    )
    record.save!
    record
  end

  def chart_images_params
    Array(params[:chart_images]).map { |chart| { title: chart[:title], data_url: chart[:data_url] } }
  end
end
