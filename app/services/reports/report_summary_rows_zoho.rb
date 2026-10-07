# Filas [label, value] relacionadas al cruce con Zoho (dueño del lead, calidad por canal,
# conversión por asesor, deals creados, horario laboral) — separado de Reports::ReportSummaryRows
# solo para no pasar el límite de tamaño de módulo; se incluye junto a él en los mismos servicios
# (Reports::WeeklyOpsReportPdfService / Reports::WeeklyOpsReportDocxService) y reusa sus helpers
# privados (`distribution_rows`/`rows_from_counts`), disponibles porque ambos módulos terminan
# mezclados en la misma clase.
module Reports::ReportSummaryRowsZoho
  # Filas [asesor, leads, % del total] — dueño del lead EN ZOHO (no asignación de conversación en
  # Chatwoot), ver V2::Reports::ZohoLeadsMetrics#summary[:by_owner].
  def owner_rows(kpis)
    distribution_rows(kpis, :by_owner)
  end

  # Filas [fuente, contestados, total, % de calidad] por Lead_Source — a diferencia de
  # #lead_source_rows (solo volumen), esto cruza calidad (Lead_Status == Contacted) por fuente.
  def quality_by_source_rows(kpis)
    quality_by_source = (kpis[:zoho_leads] || {})[:quality_by_source] || {}

    quality_by_source.map do |source, data|
      total = data[:total].to_i
      quality = data[:quality].to_i
      percent_text = total.positive? ? "#{(quality.to_f / total * 100).round(1)}%" : '0%'
      [source, quality.to_s, total.to_s, percent_text]
    end
  end

  # Total del desarrollo, no por asesor — ver V2::Reports::ZohoLeadsMetrics#conversion_totals.
  # Ambos lados son leads NUEVOS del periodo (ver ZohoLeadsMetrics#lost_count) — antes "descartados"
  # incluía leads viejos en seguimiento, mezclando ese número contra "convertidos" (solo nuevos).
  def conversion_totals_line_text(kpis)
    totals = kpis[:conversion_totals]
    return nil if totals.blank?

    "Conversión y descarte (leads nuevos del periodo): #{totals[:converted]} convertidos — #{totals[:lost]} descartados"
  end

  def deals_created_line_text(kpis)
    deals = kpis[:deals_created]
    return nil if deals.blank?

    "Deals creados: #{deals[:total]} (% conversión: #{deals[:conversion_rate]}%)"
  end

  # Deals creados en el periodo por su etapa ACTUAL — distinto del embudo de ventas, que solo
  # cuenta deals de leads cuya primera conversación cayó en el periodo (ver
  # V2::Reports::ZohoLeadsMetrics#deals_activity para el caso real que motivó esto).
  def deals_activity_line_text(kpis)
    activity = kpis[:deals_activity]
    return nil if activity.blank?

    "Deals que avanzaron esta semana: #{activity[:total]} creados — #{activity[:visita_efectiva]} con visita efectiva — " \
      "#{activity[:closed_won]} cerrados ganados"
  end

  # Filas [motivo, cantidad, % del total de leads descartados] — el % es sobre la suma de motivos,
  # no sobre el total de leads (mismo criterio que usaba el reporte semanal anterior en Python).
  # Separadas en las dos mismas poblaciones que la distribución del pipeline (ver
  # V2::Reports::ZohoLeadsMetrics#discard_breakdown): un lead que llegó antes del periodo y se
  # descartó dentro de él no es un descarte "del periodo" comparable contra los leads nuevos.
  def discard_reason_new_rows(kpis)
    discard_rows(kpis, :discard_reasons_new)
  end

  def discard_reason_follow_up_rows(kpis)
    discard_rows(kpis, :discard_reasons_follow_up)
  end

  # Total combinado — solo se usa como respaldo al exportar un reporte generado ANTES de que los
  # descartes se separaran (esos kpis persistidos no traen las dos llaves nuevas).
  def discard_reason_rows(kpis)
    discard_rows(kpis, :discard_reasons)
  end

  def discard_counts(kpis)
    zoho_leads = kpis[:zoho_leads] || {}
    { new: zoho_leads[:discarded_new_count].to_i, follow_up: zoho_leads[:discarded_follow_up_count].to_i }
  end

  def schedule_distribution_line_text(kpis)
    schedule = kpis[:schedule_distribution]
    return nil if schedule.blank?

    within = schedule[:within_business_hours]
    outside = schedule[:outside_business_hours]
    "Leads en horario laboral: #{within} — fuera de horario: #{outside} (de #{schedule[:total]} totales)"
  end

  private

  def discard_rows(kpis, key)
    reasons = (kpis[:zoho_leads] || {})[key] || {}
    rows_from_counts(reasons, reasons.values.sum)
  end
end
