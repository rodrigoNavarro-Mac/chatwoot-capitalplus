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

  # Convertidos (deals nuevos, ver #deals_created) vs descartados (Lead_Status "Lost Lead") de TODO
  # el desarrollo en el periodo — no desglosado por asesor. El "Owner" de un lead/deal en Zoho no
  # necesariamente refleja qué asesor de Chatwoot atendió al cliente (ej. una sola persona cierra o
  # descarta la mayoría de los leads en Zoho sin importar quién los trabajó primero por WhatsApp),
  # así que desglosar por dueño da una lectura equivocada de qué asesor "convierte más". Detectado
  # 2026-08-18: el desglose por asesor mostraba a un solo asesor con toda la conversión.
  def conversion_totals
    return nil if leads.blank? && deals.blank?

    { converted: deals.size, lost: leads.count { |lead| lead['Lead_Status'] == LOST_LEAD_STATUS } }
  end

  # De los leads con actividad en el periodo (ver Crm::Zoho::LeadsForPeriodService — filtra por
  # Modified_Time, no por Created_Time), cuántos se CREARON dentro/fuera del horario laboral del
  # inbox. Para un lead viejo que recién se tocó esta semana, la hora de creación puede caer fuera
  # del periodo del reporte — sigue siendo la pregunta que esta sección responde ("¿a qué hora del
  # día entran los leads que estamos trabajando?"), no "¿cuándo se tocaron esta semana?".
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
