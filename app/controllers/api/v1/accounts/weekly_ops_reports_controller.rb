class Api::V1::Accounts::WeeklyOpsReportsController < Api::V1::Accounts::BaseController
  include DateRangeHelper
  include CsvExportHelper

  before_action :fetch_inbox
  before_action :check_authorization
  before_action :fetch_weekly_ops_report, only: [:show, :pdf, :leads_export, :leads_audit, :no_contact_leads]

  # Filas mostradas en la sección "Auditoría" dentro del reporte (ver #leads_audit) -- el CSV
  # completo (#leads_export) no tiene este tope, es solo para no mandar un JSON gigante a la
  # pantalla cuando el periodo trae miles de leads.
  MAX_AUDIT_ROWS = 500

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

  # Desglose completo de leads/deals de Zoho del PERIODO EXACTO de este reporte -- para que quien
  # audita un reporte (ej. un asesor que reporta un número distinto al que ve en pantalla, como el
  # caso de Eunice/Fuego septiembre 2026) pueda verificar fila por fila contra el CRM, no solo
  # contra el total agregado. Reusa V2::Reports::RevenueIntelligenceLeadsExportBuilder -- misma
  # fuente que ya usa el dashboard de Revenue Intelligence (el data mart local de Leads/Deals, no
  # una llamada en vivo a Zoho), así que el número de este export y el de esa pantalla siempre
  # coinciden entre sí.
  def leads_export
    @report_data = V2::Reports::RevenueIntelligenceLeadsExportBuilder.new(account: Current.account, params: leads_export_params).build
    generate_csv("leads-deals-#{@inbox.name.parameterize}-#{@weekly_ops_report.period_start}", 'api/v2/accounts/reports/revenue_intelligence_leads')
  end

  # Sección "Auditoría" visible en pantalla dentro del reporte -- a diferencia de #leads_export
  # (el CSV completo para descargar), esto es lo que el usuario VE sin salir de la página, con un
  # tope de MAX_AUDIT_ROWS filas. Mismo builder/data mart que #leads_export, así que los números
  # de ambos y los de Revenue Intelligence siempre coinciden entre sí.
  def leads_audit
    rows = V2::Reports::RevenueIntelligenceLeadsExportBuilder.new(account: Current.account, params: leads_export_params).build
    render json: { total_matching_count: rows.size, rows: rows.first(MAX_AUDIT_ROWS) }
  end

  # Leads de este desarrollo/periodo sin NINGÚN seguimiento humano registrado (ni llamada, ni
  # WhatsApp, ni marcado "Contactado"/descartado en Zoho) -- ver
  # V2::Reports::WeeklyOpsReportNoContactLeadsBuilder para el porqué reusa el signal_type
  # 'lead_no_contact' que ya mantiene RevenueIntelligence::DetectRisksJob, en vez de inventar un
  # criterio nuevo. Caso real que lo motivó: Fuego/septiembre 2026, al reconciliar "Leads totales"
  # del embudo contra el total de Zoho.
  def no_contact_leads
    result = V2::Reports::WeeklyOpsReportNoContactLeadsBuilder.new(account: Current.account, params: leads_export_params).build
    render json: result
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

  # since/until en unix COMO STRING -- DateRangeHelper#parse_date_time hace
  # DateTime.strptime(datetime, '%s'), que exige un string (así llegan siempre desde params[] de
  # una request real) y revienta con TypeError si se le pasa un Integer directo (bug real
  # encontrado en producción 2026-10-07: tanto #leads_export como #leads_audit tiraban 500).
  # Reconstruidos a partir de period_start/period_end (fechas, no datetimes) en la zona horaria
  # del inbox, con el mismo criterio exclusivo-por-la-derecha que usa
  # V2::Reports::WeeklyOpsReportBuilder#date_bounds: el rango real termina al INICIO del día
  # siguiente a period_end, no al final de period_end mismo.
  def leads_export_params
    since = @weekly_ops_report.period_start.in_time_zone(@inbox.timezone).beginning_of_day
    until_time = (@weekly_ops_report.period_end + 1.day).in_time_zone(@inbox.timezone).beginning_of_day

    { since: since.to_i.to_s, until: until_time.to_i.to_s, desarrollo: development_key }
  end

  def development_key
    @inbox.agent_bot&.bot_config&.dig('variables', 'desarrollo')
  end
end
