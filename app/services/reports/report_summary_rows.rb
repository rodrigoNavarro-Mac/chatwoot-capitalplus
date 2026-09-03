# Filas [label, value] del resumen de KPIs del reporte semanal operativo — compartidas entre
# Reports::WeeklyOpsReportPdfService (Prawn) y Reports::WeeklyOpsReportDocxService (membrete .docx)
# para que ambos formatos de salida muestren exactamente los mismos números.
module Reports::ReportSummaryRows
  # Mismos labels que SALES_FUNNEL_REPORTS.STAGES en report.json (es) — el PDF/DOCX no pasa por
  # i18n, así que se hardcodean en español aquí igual que el resto de los títulos de este servicio.
  STAGE_LABELS = {
    'leads' => 'Leads totales',
    'customer_replied' => 'Contestados por el cliente',
    'has_deal' => 'Con deal en Zoho',
    'visita_efectiva' => 'Visita efectiva',
    'closed_won' => 'Deal cerrado ganado'
  }.freeze

  # Filas [etapa, cantidad, % real, % meta, diferencia] del embudo de ventas — mismo dato que
  # V2::Reports::SalesFunnelBuilder#build_row (ver V2::Reports::WeeklyOpsReportBuilder#pipeline_metrics,
  # que reusa ese builder para el inbox del reporte).
  def funnel_rows(kpis)
    stages = (kpis[:pipeline] || {})[:stages] || []

    stages.map do |stage|
      row = [
        STAGE_LABELS[stage[:stage]] || stage[:stage],
        funnel_count_text(stage),
        percent(stage[:actual_percent]),
        percent(stage[:target_percent]),
        percent(stage[:delta])
      ]
      row.map { |value| value.nil? ? '—' : value.to_s }
    end
  end

  # "5 (+2 actividad, +1 externo, -3 reactivados)" cuando parte del conteo viene de deals fuera de
  # la cohorte de leads nuevos (ver V2::Reports::SalesFunnelDealActivity) o se excluyeron leads
  # reactivados (ver V2::Reports::SalesFunnelReactivatedLeads) — el PDF/DOCX no tiene una barra de
  # colores como el frontend, así que esa porción se anota en la misma celda en vez de perderse.
  def funnel_count_text(stage)
    parts = [
      ("+#{stage[:activity_count]} actividad" if stage[:activity_count].to_i.positive?),
      ("+#{stage[:external_count]} externo" if stage[:external_count].to_i.positive?),
      ("-#{stage[:reactivated_count]} reactivados" if stage[:reactivated_count].to_i.positive?)
    ].compact
    return stage[:count] if parts.empty?

    "#{stage[:count]} (#{parts.join(', ')})"
  end

  def summary_rows(kpis)
    contact_time = kpis[:contact_time] || {}
    volume = kpis[:volume] || {}
    cadences = kpis[:cadences] || {}
    campaigns = kpis[:campaigns] || {}

    rows = [
      ['Conversaciones nuevas', volume[:new_conversations]],
      ['Tiempo hasta primer mensaje de asesor (min)', contact_time[:first_response]],
      ['Tiempo de respuesta inicial (min)', contact_time[:reply_time]],
      ['Leads inscritos en cadencia', cadences[:total_enrollments]],
      ['Tasa de respuesta de cadencia', percent(cadences[:response_rate])],
      ['Mensajes de campaña enviados', campaigns[:messages_sent]]
    ]
    rows.map { |label, value| [label, value.nil? ? '—' : value.to_s] }
  end

  # Filas [nombre, conversaciones, tiempo 1er mensaje, tiempo de respuesta] del desglose por
  # asesor — mismo dato que V2::Reports::WeeklyOpsReportBuilder#by_advisor_metrics, ya ordenado
  # por conversations_count descendente.
  def advisor_rows(kpis)
    advisors = kpis[:by_advisor] || []

    advisors.map do |advisor|
      contact_time = advisor[:contact_time] || {}
      row = [advisor[:name], advisor[:conversations_count], contact_time[:first_response], contact_time[:reply_time]]
      row.map { |value| value.nil? ? '—' : value.to_s }
    end
  end

  # Filas [estado, cantidad, % del total] de la distribución del pipeline de Zoho por Lead_Status
  # (Contactado, Intento de contacto, etc.), separadas en dos poblaciones — ver
  # V2::Reports::ZohoLeadsMetrics#summary para el porqué: mezclar leads nuevos del periodo con
  # leads viejos en seguimiento hacía que este total no cuadrara contra "Leads totales" del embudo
  # de ventas para el mismo periodo nominal.
  def pipeline_status_new_rows(kpis)
    zoho_leads = kpis[:zoho_leads] || {}
    rows_from_counts(zoho_leads[:by_status_new] || {}, zoho_leads[:new_count].to_i)
  end

  def pipeline_status_follow_up_rows(kpis)
    zoho_leads = kpis[:zoho_leads] || {}
    rows_from_counts(zoho_leads[:by_status_follow_up] || {}, zoho_leads[:follow_up_count].to_i)
  end

  # Filas [fuente, cantidad, % del total de leads] por Lead_Source (Facebook Ads, Google Ads, etc.)
  def lead_source_rows(kpis)
    distribution_rows(kpis, :by_source)
  end

  # Filas [motivo, cantidad, % del total de leads descartados] — el % es sobre la suma de motivos,
  # no sobre el total de leads (mismo criterio que usaba el reporte semanal anterior en Python).
  def discard_reason_rows(kpis)
    reasons = (kpis[:zoho_leads] || {})[:discard_reasons] || {}
    rows_from_counts(reasons, reasons.values.sum)
  end

  # Filas [nombre, llamadas, % contestadas, duración promedio] del desglose de llamadas de Aircall
  # por asesor — ver V2::Reports::WeeklyOpsReportBuilder#calls_by_advisor.
  def call_advisor_rows(kpis)
    advisors = (kpis[:aircall_calls] || {})[:by_advisor] || []

    advisors.map do |advisor|
      row = [advisor[:name], advisor[:total], percent(advisor[:answered_percent]), format_duration(advisor[:avg_duration_seconds])]
      row.map { |value| value.nil? ? '—' : value.to_s }
    end
  end

  def call_summary_line_text(kpis)
    calls = kpis[:aircall_calls]
    return nil if calls.blank?

    "Llamadas: #{calls[:total]} (#{calls[:answered_percent]}% contestadas, #{calls[:incoming]} entrantes / #{calls[:outgoing]} salientes)"
  end

  def format_duration(seconds)
    return nil if seconds.nil?

    "#{seconds / 60}m #{seconds % 60}s"
  end

  private

  def distribution_rows(kpis, key)
    zoho_leads = kpis[:zoho_leads] || {}
    counts = zoho_leads[key] || {}
    rows_from_counts(counts, zoho_leads[:total].to_i)
  end

  def rows_from_counts(counts, total)
    counts.map do |label, count|
      percent_text = total.positive? ? "#{(count.to_f / total * 100).round(1)}%" : '0%'
      [label, count.to_s, percent_text]
    end
  end

  def percent(value)
    return nil if value.nil?

    "#{value}%"
  end
end
