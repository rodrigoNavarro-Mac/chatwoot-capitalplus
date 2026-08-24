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
  #
  # `leads` mezcla dos poblaciones (ver Crm::Zoho::LeadsForPeriodService: filtra por Modified_Time,
  # no Created_Time) — un lead nuevo de esta semana y un lead de hace meses que apenas se tocó hoy
  # cuentan igual. Comparar ese total directo contra "Leads totales" del embudo de ventas (que sí es
  # solo leads nuevos, ver V2::Reports::SalesFunnelBuilder) generaba una lectura confusa: la
  # distribución del pipeline salía ~5x más grande que el embudo para el mismo periodo nominal.
  # `by_status` se separa en `by_status_new`/`by_status_follow_up` (mismo criterio de "nuevo" que el
  # embudo: Created_Time dentro del rango) para que se pueda comparar 1:1 contra el embudo sin ese
  # sesgo. El resto de los desgloses (fuente, dueño, motivo de descarte) se dejan sobre el total
  # combinado a propósito: no tienen un equivalente en el embudo contra el cual generen la misma
  # comparación engañosa.
  def summary
    return nil if leads.blank?

    volume_counts.merge(status_breakdown).merge(source_and_owner_breakdown).merge(quality_breakdown)
  end

  # Deals de Zoho CREADOS en este periodo (no "tiene deal" acumulado, como el embudo de ventas) y
  # qué % de los leads NUEVOS del periodo ya se tradujo en un deal nuevo — el denominador usa
  # `new_leads`, no el total mezclado de `leads`, para que el % no salga diluido por leads viejos
  # que solo se tocaron esta semana y nunca podrían convertirse "en el periodo" en primer lugar.
  def deals_created
    return nil if development_key.blank? || range.blank?

    { total: deals.size, conversion_rate: safe_rate(deals.size, new_leads.size) }
  end

  # De los deals CREADOS en este periodo (misma colección que #deals_created), cuántos ya están en
  # "Visita efectiva"/"Cerrado ganado" a día de hoy — a diferencia del embudo de ventas
  # (V2::Reports::SalesFunnelBuilder), que solo cuenta deals de leads cuya PRIMERA conversación de
  # Chatwoot cayó en este periodo. Un lead que llegó hace semanas y cuyo deal se creó esta semana
  # (caso real detectado 2026-08-24: deal creado y visto en el kanban de Zoho la misma semana, pero
  # "Con deal en Zoho" del embudo salía en 0 porque el lead había llegado antes del periodo) SÍ
  # cuenta aquí, aunque el embudo lo excluya por diseño (cohorte, no actividad).
  #
  # OJO: no captura un deal VIEJO que solo avanzó de etapa esta semana sin haberse creado en el
  # periodo — eso requeriría el historial de cambios de etapa de Zoho (Stage_History), que esta
  # integración no consulta. Es "de lo nuevo, qué tan lejos llegó", no "todo lo que se movió".
  def deals_activity
    return nil if development_key.blank? || range.blank? || deals.blank?

    {
      total: deals.size,
      visita_efectiva: deals.count { |deal| V2::Reports::SalesFunnelBuilder::VISITA_EFECTIVA_STAGES.include?(deal['Stage']) },
      closed_won: deals.count { |deal| V2::Reports::SalesFunnelBuilder::CLOSED_WON_STAGES.include?(deal['Stage']) }
    }
  end

  # Cuántos leads NUEVOS del periodo (mismo criterio que "convertidos" del embudo: Created_Time
  # dentro del rango) se marcaron como perdidos (Lead_Status "Cliente perdido/Descartado").
  # Restringido a nuevos (antes contaba TODOS los leads tocados, incluyendo seguimiento de leads
  # viejos) para que sea comparable 1:1 contra "convertidos" en
  # V2::Reports::WeeklyOpsReportBuilder#conversion_totals — antes esa línea comparaba un numerador
  # "solo nuevos" contra un denominador implícito "nuevos + seguimiento", el mismo sesgo detectado
  # en #summary. No vive aquí como un solo hash porque "convertidos" ya no sale de una cuenta
  # independiente contra Deals de Zoho (ver builder para el porqué).
  def lost_count
    new_leads.count { |lead| lead['Lead_Status'] == LOST_LEAD_STATUS }
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

  # "Nuevo" = Created_Time cae dentro del rango del reporte, el mismo criterio con el que
  # V2::Reports::SalesFunnelBuilder arma "Leads totales" del embudo (primera conversación del
  # contacto creada en el periodo). El resto de `leads` (Created_Time anterior al rango, pero con
  # Modified_Time dentro — ver Crm::Zoho::LeadsForPeriodService) es "seguimiento": leads viejos que
  # un asesor tocó esta semana/mes sin que sean una llegada nueva.
  def new_leads
    partitioned_leads.first
  end

  def follow_up_leads
    partitioned_leads.last
  end

  def partitioned_leads
    @partitioned_leads ||= leads.partition { |lead| created_within_range?(lead) }
  end

  def created_within_range?(lead)
    created_at = lead['Created_Time']
    return false if created_at.blank?

    range.cover?(Time.zone.parse(created_at))
  end

  def volume_counts
    { total: leads.size, new_count: new_leads.size, follow_up_count: follow_up_leads.size }
  end

  def status_breakdown
    {
      by_status: count_by(leads, 'Lead_Status'),
      by_status_new: count_by(new_leads, 'Lead_Status'),
      by_status_follow_up: count_by(follow_up_leads, 'Lead_Status')
    }
  end

  def source_and_owner_breakdown
    {
      by_source: count_by(leads, 'Lead_Source'),
      discard_reasons: count_by(lost_leads, 'Raz_n_de_descarte'),
      by_owner: count_by(leads) { |lead| lead.dig('Owner', 'name') }
    }
  end

  def quality_breakdown
    quality_count = leads.count { |lead| lead['Lead_Status'] == CONTACTED_STATUS }

    {
      quality_leads_count: quality_count,
      quality_leads_percent: safe_rate(quality_count, leads.size),
      quality_by_source: quality_by_source
    }
  end

  def lost_leads
    leads.select { |lead| lead['Lead_Status'] == LOST_LEAD_STATUS }
  end

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
