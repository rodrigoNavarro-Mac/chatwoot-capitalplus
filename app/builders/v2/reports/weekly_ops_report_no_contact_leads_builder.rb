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

  MAX_ROWS = 200

  # params: { since:, until:, desarrollo: } -- mismo shape que
  # V2::Reports::RevenueIntelligenceLeadsExportBuilder (since/until como STRING unix, ver
  # DateRangeHelper#parse_date_time) para poder pasarle directo leads_export_params del controller
  # sin armar un Range aparte.
  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    return { total_count: 0, rows: [] } if development_key.blank? || range.blank?

    lead_ids = leads_in_scope.ids
    return { total_count: 0, rows: [] } if lead_ids.empty?

    signals = open_signals_for(lead_ids)
    leads_by_id = account.revenue_leads.where(id: signals.map(&:subject_id)).index_by(&:id)

    { total_count: signals.size, rows: signals.first(MAX_ROWS).filter_map { |signal| signal_row(signal, leads_by_id[signal.subject_id]) } }
  end

  private

  attr_reader :account, :params

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
