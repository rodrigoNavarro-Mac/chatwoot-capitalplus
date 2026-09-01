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
      by_advisor: by_advisor,
      voicemail: voicemail_metrics
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

  # "Contestada" (Call#status == 'completed') no distingue una persona real de un buzón de voz o
  # contestadora — Aircall marca answered_at en ambos casos (hallazgo real 2026-09-01, ver el fix
  # equivalente en V2::Reports::SalesFunnelBuilder#answered_call_conversation_ids). Solo se puede
  # saber la diferencia leyendo la transcripción vía CallAnalysis, así que esta sección depende de
  # cuántas llamadas del período ya se analizaron — `not_yet_analyzed` deja claro cuando el dato es
  # parcial. nil si ninguna llamada contestada del período tiene análisis todavía.
  def voicemail_metrics
    analyzed = CallAnalysis.completed_scope.where(call_id: answered_scope.select(:id)).includes(:call)
    return nil if analyzed.empty?

    voicemail_analyses = analyzed.select { |call_analysis| call_analysis.confidence == 'low' }
    not_yet_analyzed = answered_scope.count - analyzed.size

    return empty_voicemail_metrics(not_yet_analyzed) if voicemail_analyses.empty?

    voicemail_metrics_for(voicemail_analyses, not_yet_analyzed)
  end

  def voicemail_metrics_for(voicemail_analyses, not_yet_analyzed)
    recovery_hours = voicemail_analyses.filter_map { |call_analysis| recovery_hours_for(call_analysis) }

    {
      count: voicemail_analyses.size,
      percent_of_answered: safe_rate(voicemail_analyses.size, answered_scope.count),
      recovered_count: recovery_hours.size,
      recovered_percent: safe_rate(recovery_hours.size, voicemail_analyses.size),
      avg_recovery_hours: recovery_hours.presence && (recovery_hours.sum / recovery_hours.size).round(1),
      not_yet_analyzed: not_yet_analyzed
    }
  end

  def empty_voicemail_metrics(not_yet_analyzed)
    { count: 0, percent_of_answered: 0.0, recovered_count: 0, recovered_percent: 0.0,
      avg_recovery_hours: nil, not_yet_analyzed: not_yet_analyzed }
  end

  # Horas hasta la primera llamada REAL (confidence != low, ya analizada) posterior a esta llamada
  # de buzón, en la misma conversación — nil si el lead nunca volvió a contestar de verdad.
  def recovery_hours_for(voicemail_analysis)
    voicemail_call = voicemail_analysis.call
    next_real_call = Call.where(conversation_id: voicemail_call.conversation_id)
                         .where('started_at > ?', voicemail_call.started_at)
                         .joins(:call_analysis)
                         .where.not(call_analyses: { confidence: 'low' })
                         .order(:started_at)
                         .first

    return nil if next_real_call.blank?

    ((next_real_call.started_at - voicemail_call.started_at) / 1.hour).round(1)
  end

  def safe_rate(numerator, denominator)
    return 0.0 if denominator.to_i.zero?

    (numerator.to_f / denominator * 100).round(2)
  end
end
