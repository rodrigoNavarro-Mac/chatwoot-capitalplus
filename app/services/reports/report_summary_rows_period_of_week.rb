# Filas [label, value] con el desglose entre semana (L-V) vs fin de semana (S-D) — separado de
# Reports::ReportSummaryRows solo por límite de tamaño de módulo, ver esa clase para el resto de
# las filas del resumen.
module Reports::ReportSummaryRowsPeriodOfWeek
  # Filas [periodo, tiempo 1er mensaje, tiempo de respuesta] — entre semana (L-V) vs fin de semana
  # (S-D), ver V2::Reports::WeeklyOpsReportBuilder#contact_time_by_period_of_week.
  def contact_time_by_period_rows(kpis)
    by_period = kpis[:contact_time_by_period_of_week]
    return [] if by_period.blank?

    [['Entre semana (L-V)', :weekday], ['Fin de semana (S-D)', :weekend]].map do |label, key|
      times = by_period[key] || {}
      row = [label, times[:first_response], times[:reply_time]]
      row.map { |value| value.nil? ? '—' : value.to_s }
    end
  end

  # Filas [asesor, tiempo 1er mensaje L-V, tiempo 1er mensaje S-D, "leads L-V / S-D"] — mismo dato
  # que #advisor_rows pero desglosado por periodo de la semana, ver
  # V2::Reports::WeeklyOpsReportBuilder#advisor_period_of_week_stats.
  def advisor_period_of_week_rows(kpis)
    advisors = kpis[:by_advisor] || []
    return [] if advisors.none? { |advisor| advisor[:by_period_of_week].present? }

    advisors.map { |advisor| advisor_period_of_week_row(advisor) }
  end

  private

  def advisor_period_of_week_row(advisor)
    by_period = advisor[:by_period_of_week] || {}
    weekday_response, weekday_count = period_of_week_stats(by_period[:weekday])
    weekend_response, weekend_count = period_of_week_stats(by_period[:weekend])

    row = [advisor[:name], weekday_response, weekend_response, "#{weekday_count} / #{weekend_count}"]
    row.map { |value| value.nil? ? '—' : value.to_s }
  end

  def period_of_week_stats(period)
    period ||= {}
    [period.dig(:contact_time, :first_response), period[:conversations_count] || 0]
  end
end
