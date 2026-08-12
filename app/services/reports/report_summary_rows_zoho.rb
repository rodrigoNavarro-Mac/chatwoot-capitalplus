# Filas [label, value] relacionadas al cruce con Zoho (dueño del lead, calidad por canal,
# conversión por asesor, deals creados, horario laboral) — separado de Reports::ReportSummaryRows
# solo para no pasar el límite de tamaño de módulo; se incluye junto a él en los mismos servicios
# (Reports::WeeklyOpsReportPdfService / Reports::WeeklyOpsReportDocxService) y reusa sus helpers
# privados (`distribution_rows`), disponibles porque ambos módulos terminan mezclados en la misma
# clase.
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

  # Filas [asesor, contestados, descartados] — ver V2::Reports::ZohoLeadsMetrics#conversion_by_owner.
  def conversion_by_owner_rows(kpis)
    (kpis[:conversion_by_owner] || []).map { |row| [row[:owner], row[:contacted].to_s, row[:lost].to_s] }
  end

  def deals_created_line_text(kpis)
    deals = kpis[:deals_created]
    return nil if deals.blank?

    "Deals creados: #{deals[:total]} (% conversión: #{deals[:conversion_rate]}%)"
  end

  def schedule_distribution_line_text(kpis)
    schedule = kpis[:schedule_distribution]
    return nil if schedule.blank?

    within = schedule[:within_business_hours]
    outside = schedule[:outside_business_hours]
    "Leads en horario laboral: #{within} — fuera de horario: #{outside} (de #{schedule[:total]} totales)"
  end
end
