# Filas [label, value] del resumen de KPIs del reporte semanal operativo — compartidas entre
# Reports::WeeklyOpsReportPdfService (Prawn) y Reports::WeeklyOpsReportDocxService (membrete .docx)
# para que ambos formatos de salida muestren exactamente los mismos números.
module Reports::ReportSummaryRows
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

  private

  def percent(value)
    return nil if value.nil?

    "#{value}%"
  end
end
