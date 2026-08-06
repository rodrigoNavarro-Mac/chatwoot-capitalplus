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

  private

  def percent(value)
    return nil if value.nil?

    "#{value}%"
  end
end
