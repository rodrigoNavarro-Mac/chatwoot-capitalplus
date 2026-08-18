# Todo lo derivado de los leads/deals de Zoho de UN desarrollo y periodo, para el reporte semanal
# operativo — extraído de V2::Reports::WeeklyOpsReportBuilder solo para no pasar el límite de
# tamaño de esa clase (mismo criterio ya usado con WeeklyOpsReportCallsMetrics/LeadsTimelineMetrics).
#
# Consultado en vivo (Crm::Zoho::LeadsForPeriodService/DealsForPeriodService), a diferencia de
# V2::Reports::SalesFunnelBuilder que solo mira contactos que ya tienen conversación en Chatwoot.
# `leads` es público y memoizado — V2::Reports::LeadsTimelineMetrics lo reusa vía
# WeeklyOpsReportBuilder para no duplicar la llamada a Zoho.
class V2::Reports::ZohoLeadsMetrics
  # El campo Lead_Status de Leads/search para esta cuenta devuelve el LABEL EN ESPAÑOL directo
  # (ej. "Cliente perdido/Descartado", "Contactado", "Intento de contacto"), no un actual_value en
  # inglés — a diferencia de Stage en el módulo Deals (ver
  # V2::Reports::SalesFunnelBuilder::VISITA_EFECTIVA_STAGES, que sí es inglés). Un comentario previo
  # aquí afirmaba lo contrario ("confirmado contra la API real") y nunca lo fue: LOST_LEAD_STATUS/
  # CONTACTED_STATUS comparaban contra 'Lost Lead'/'Contacted', que no aparecen jamás en datos
  # reales, así que "descartados" y "leads de calidad" siempre salían en 0. Confirmado 2026-08-18
  # contra la API en vivo: 23 leads con Lead_Status == "Cliente perdido/Descartado" en una sola
  # semana, ninguno con el valor en inglés.
  LOST_LEAD_STATUS = 'Cliente perdido/Descartado'.freeze
  CONTACTED_STATUS = 'Contactado'.freeze

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
      by_status: count_by(leads, 'Lead_Status'),
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

  # Cuántos leads del desarrollo se marcaron como perdidos (Lead_Status "Cliente perdido/Descartado")
  # en el periodo.
  # Usado por V2::Reports::WeeklyOpsReportBuilder#conversion_totals junto con el conteo de
  # "convertidos" del embudo de ventas — no vive aquí como un solo hash porque "convertidos" ya no
  # sale de una cuenta independiente contra Deals de Zoho (ver builder para el porqué).
  def lost_count
    leads.count { |lead| lead['Lead_Status'] == LOST_LEAD_STATUS }
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

  def count_by(leads, field = nil, &extractor)
    extractor ||= ->(lead) { lead[field] }
    leads.filter_map(&extractor).tally
  end

  def safe_rate(numerator, denominator)
    return 0.0 if denominator.to_i.zero?

    (numerator.to_f / denominator * 100).round(2)
  end
end
