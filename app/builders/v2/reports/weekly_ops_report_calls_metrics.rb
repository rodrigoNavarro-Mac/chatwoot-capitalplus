# Sección de llamadas de Aircall (total/contestadas/duración/dirección, desglose por asesor) del
# Reporte Semanal Operativo — separado de V2::Reports::WeeklyOpsReportBuilder solo para no pasar
# el límite de tamaño de clase (mismo criterio que Reports::WeeklyOpsReportDocxTables).
class V2::Reports::WeeklyOpsReportCallsMetrics
  ANSWERED_STATUS = 'completed'.freeze

  def initialize(inbox:, range:)
    @inbox = inbox
    @range = range
  end

  # nil cuando no hay ninguna llamada de Aircall en el rango — el frontend/PDF/docx simplemente
  # omiten la sección (mismo criterio que zoho_leads_metrics).
  def build
    return nil if scope.none?

    {
      total: scope.count,
      answered: answered_scope.count,
      answered_percent: safe_rate(answered_scope.count, scope.count),
      avg_duration_seconds: answered_scope.average(:duration_seconds)&.round,
      incoming: scope.incoming.count,
      outgoing: scope.outgoing.count,
      by_advisor: by_advisor
    }
  end

  private

  attr_reader :inbox, :range

  def scope
    @scope ||= range.present? ? inbox.calls.aircall.where(started_at: range) : inbox.calls.aircall
  end

  def answered_scope
    scope.where(status: ANSWERED_STATUS)
  end

  def by_advisor
    agent_ids = scope.where.not(accepted_by_agent_id: nil).distinct.pluck(:accepted_by_agent_id)
    stats = agent_ids.map { |user_id| advisor_stats(user_id) }
    stats.sort_by { |advisor| -advisor[:total] }
  end

  def advisor_stats(user_id)
    agent_scope = scope.where(accepted_by_agent_id: user_id)
    answered = agent_scope.where(status: ANSWERED_STATUS)

    {
      user_id: user_id,
      name: advisor_name(user_id),
      total: agent_scope.count,
      answered: answered.count,
      answered_percent: safe_rate(answered.count, agent_scope.count),
      avg_duration_seconds: answered.average(:duration_seconds)&.round
    }
  end

  def advisor_name(user_id)
    User.find_by(id: user_id)&.name || "Agente #{user_id}"
  end

  def safe_rate(numerator, denominator)
    return 0.0 if denominator.to_i.zero?

    (numerator.to_f / denominator * 100).round(2)
  end
end
