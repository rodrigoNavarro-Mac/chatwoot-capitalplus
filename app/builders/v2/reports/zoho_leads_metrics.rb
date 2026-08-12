# Todo lo derivado de los leads/deals de Zoho de UN desarrollo y periodo, para el reporte semanal
# operativo — extraído de V2::Reports::WeeklyOpsReportBuilder solo para no pasar el límite de
# tamaño de esa clase (mismo criterio ya usado con WeeklyOpsReportCallsMetrics/LeadsTimelineMetrics).
#
# Consultado en vivo (Crm::Zoho::LeadsForPeriodService/DealsForPeriodService), a diferencia de
# V2::Reports::SalesFunnelBuilder que solo mira contactos que ya tienen conversación en Chatwoot.
# `leads` es público y memoizado — V2::Reports::LeadsTimelineMetrics lo reusa vía
# WeeklyOpsReportBuilder para no duplicar la llamada a Zoho.
class V2::Reports::ZohoLeadsMetrics
  # Valores internos ("actual_value") del campo Lead_Status en Zoho de esta cuenta, confirmados
  # contra la API real — no son los labels en español que se ven en la UI de Zoho (que están
  # traducidos). Mismo criterio que V2::Reports::SalesFunnelBuilder::VISITA_EFECTIVA_STAGES.
  LEAD_STATUS_LABELS = {
    'Nuevo contacto' => 'Nuevo contacto',
    'Attempted to Contact' => 'Intento de contacto',
    'Contact in Future' => 'Contactar en el futuro',
    'Contacted' => 'Contactado',
    'Calificado' => 'Calificado',
    'Lost Lead' => 'Cliente perdido/Descartado',
    'Pre-Qualified' => 'Previamente clasificado',
    'Not Contacted' => 'Contacto no exitoso',
    'Not Qualified' => 'No habilitado',
    'Junk Lead' => 'Posible cliente no solicitado'
  }.freeze
  LOST_LEAD_STATUS = 'Lost Lead'.freeze
  CONTACTED_STATUS = 'Contacted'.freeze

  def initialize(account:, development_key:, range:, inbox:)
    @account = account
    @development_key = development_key
    @range = range
    @inbox = inbox
  end

  # nil si el inbox no tiene "desarrollo" configurado, o Zoho no responde, o no hay leads en el
  # periodo — el frontend/PDF/docx simplemente omiten la sección.
  def summary
    return nil if leads.blank?

    lost_leads = leads.select { |lead| lead['Lead_Status'] == LOST_LEAD_STATUS }
    quality_count = leads.count { |lead| lead['Lead_Status'] == CONTACTED_STATUS }

    {
      total: leads.size,
      by_status: count_by(leads, 'Lead_Status', LEAD_STATUS_LABELS),
      by_source: count_by(leads, 'Lead_Source'),
      discard_reasons: count_by(lost_leads, 'Raz_n_de_descarte'),
      quality_leads_count: quality_count,
      quality_leads_percent: safe_rate(quality_count, leads.size),
      by_owner: count_by(leads) { |lead| lead.dig('Owner', 'name') },
      quality_by_source: quality_by_source
    }
  end

  # Deals de Zoho CREADOS en este periodo (no "tiene deal" acumulado, como el embudo de ventas) y
  # qué % de los leads del periodo ya se tradujo en un deal nuevo.
  def deals_created
    return nil if development_key.blank? || range.blank?

    { total: deals.size, conversion_rate: safe_rate(deals.size, leads.size) }
  end

  # Cuántos leads de cada dueño (Owner en Zoho) se contestaron vs se descartaron en el periodo,
  # ordenado por volumen total descendente.
  def conversion_by_owner
    return [] if leads.blank?

    rows = leads.group_by { |lead| lead.dig('Owner', 'name') }.except(nil).map do |owner, owned|
      { owner: owner, contacted: owned.count { |lead| lead['Lead_Status'] == CONTACTED_STATUS },
        lost: owned.count { |lead| lead['Lead_Status'] == LOST_LEAD_STATUS } }
    end
    rows.sort_by { |row| -(row[:contacted] + row[:lost]) }
  end

  # Cuántos leads del periodo se crearon dentro/fuera del horario laboral configurado del inbox.
  def schedule_distribution
    return nil if leads.blank?

    classifier = V2::Reports::BusinessHoursClassifier.new(inbox)
    within = leads.count { |lead| classifier.within_business_hours?(Time.zone.parse(lead['Created_Time'].to_s)) }

    { within_business_hours: within, outside_business_hours: leads.size - within, total: leads.size }
  end

  def leads
    @leads ||= Crm::Zoho::LeadsForPeriodService.new(account: account, development_key: development_key, range: range).fetch
  end

  private

  attr_reader :account, :development_key, :range, :inbox

  def deals
    @deals ||= Crm::Zoho::DealsForPeriodService.new(account: account, development_key: development_key, range: range).fetch
  end

  def quality_by_source
    leads.group_by { |lead| lead['Lead_Source'] }.except(nil).transform_values do |group|
      { total: group.size, quality: group.count { |lead| lead['Lead_Status'] == CONTACTED_STATUS } }
    end
  end

  def count_by(leads, field = nil, labels = nil, &extractor)
    extractor ||= ->(lead) { lead[field] }
    values = leads.filter_map(&extractor)
    values.tally.transform_keys { |value| labels ? labels.fetch(value, value) : value }
  end

  def safe_rate(numerator, denominator)
    return 0.0 if denominator.to_i.zero?

    (numerator.to_f / denominator * 100).round(2)
  end
end
