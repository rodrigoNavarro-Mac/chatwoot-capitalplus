# Leads de ESTE desarrollo/periodo que quedaron sin ningún seguimiento humano real -- reusa el
# mismo signal_type 'lead_no_contact' que ya detecta y mantiene abierto/cerrado
# RevenueIntelligence::DetectRisksJob (ver detect_lead_no_contact: first_contact_at nil Y
# discard_reason nil, es decir ni se le marcó "Contactado" en Zoho ni se descartó con una razón --
# un lead ya descartado (aunque sea por "ilocalizable" fuera de Aircall/Chatwoot) SÍ tuvo
# seguimiento, solo que no quedó registrado en un canal que este sistema audite).
#
# Caso real que motivó esto (Fuego, septiembre 2026): el reporte semanal solo mostraba el total
# agregado de leads -- no había forma de ver CUÁLES, de ese total, nunca recibieron ni una llamada
# ni un mensaje. Esta sección cierra ese hueco con la misma regla ya validada que usa Revenue
# Intelligence, sin duplicar lógica de negocio nueva.
class V2::Reports::WeeklyOpsReportNoContactLeadsBuilder
  include DateRangeHelper

  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  # params: { since:, until:, desarrollo:, page:, per_page: } -- since/until mismo shape que
  # V2::Reports::RevenueIntelligenceLeadsExportBuilder (STRING unix, ver
  # DateRangeHelper#parse_date_time) para poder pasarle directo leads_export_params del controller
  # sin armar un Range aparte. page/per_page son opcionales -- default page 1, DEFAULT_PER_PAGE.
  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    return empty_result if development_key.blank? || range.blank?

    lead_ids = leads_in_scope.ids
    return empty_result if lead_ids.empty?

    paginated_result(open_signals_for(lead_ids))
  end

  private

  attr_reader :account, :params

  def paginated_result(signals)
    total = signals.size
    page_signals = signals.offset((page - 1) * per_page).limit(per_page)

    { total_count: total, page: page, per_page: per_page, total_pages: total_pages(total), rows: rows_for(page_signals) }
  end

  def rows_for(page_signals)
    leads_by_id = account.revenue_leads.where(id: page_signals.map(&:subject_id)).index_by(&:id)
    page_signals.filter_map { |signal| signal_row(signal, leads_by_id[signal.subject_id]) }
  end

  def empty_result
    { total_count: 0, page: 1, per_page: per_page, total_pages: 0, rows: [] }
  end

  def page
    @page ||= [params[:page].to_i, 1].max
  end

  def per_page
    @per_page ||= params[:per_page].presence&.to_i&.clamp(1, MAX_PER_PAGE) || DEFAULT_PER_PAGE
  end

  def total_pages(total)
    (total.to_f / per_page).ceil
  end

  def development_key
    params[:desarrollo]
  end

  def leads_in_scope
    account.revenue_leads.where(desarrollo: development_key, created_at_source: range)
  end

  def open_signals_for(lead_ids)
    account.revenue_risk_signals.open
           .where(signal_type: 'lead_no_contact', subject_type: 'RevenueLead', subject_id: lead_ids)
           .order(detected_at: :desc)
  end

  def signal_row(signal, lead)
    return nil if lead.nil?

    payload = lead.raw_payload || {}
    {
      zoho_lead_id: lead.zoho_lead_id,
      nombre: "#{payload['First_Name']} #{payload['Last_Name']}".strip.presence,
      telefono: (payload['Phone'] || payload['Mobile']).presence,
      fuente: lead.lead_source,
      dueno: lead.owner_name,
      creado: lead.created_at_source&.strftime('%Y-%m-%d %H:%M'),
      horas_sin_contacto: signal.context['hours_since_created']
    }
  end
end
