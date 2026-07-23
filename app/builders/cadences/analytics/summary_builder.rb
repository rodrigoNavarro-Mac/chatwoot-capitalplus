class Cadences::Analytics::SummaryBuilder < Cadences::Analytics::BaseBuilder
  def build
    {
      leads_in_cadence: leads_in_cadence,
      responded_count: responded_count,
      response_rate: safe_rate(responded_count, leads_in_cadence),
      no_response_rate: safe_rate(leads_in_cadence - responded_count, leads_in_cadence),
      call_tasks_created: call_tasks_created,
      calls_completed: calls_completed,
      call_compliance_rate: safe_rate(calls_completed, call_tasks_created),
      avg_lead_response_time_seconds: avg_lead_response_time,
      avg_agent_action_time_seconds: avg_agent_action_time,
      recovered_count: recovered_count,
      cold_count: cold_count,
      abandonment_rate: safe_rate(cold_count, leads_in_cadence),
      recovered_rate: safe_rate(recovered_count, leads_in_cadence)
    }
  end

  private

  def leads_in_cadence
    @leads_in_cadence ||= enrollment_scope.count
  end

  def responded_count
    @responded_count ||= enrollment_scope.where(status: RESPONDED_STATUSES).count
  end

  def call_tasks_created
    @call_tasks_created ||= call_task_scope.count
  end

  def calls_completed
    @calls_completed ||= call_task_scope.completed.count
  end

  def recovered_count
    @recovered_count ||= enrollment_scope.recovered.count
  end

  def cold_count
    @cold_count ||= enrollment_scope.cold.count
  end

  def avg_lead_response_time
    pairs = enrollment_scope.where(status: RESPONDED_STATUSES).pluck(:last_template_sent_at, :last_lead_response_at)
    average_seconds(pairs)
  end

  def avg_agent_action_time
    pairs = call_task_scope.completed.pluck(:notified_at, :completed_at)
    average_seconds(pairs)
  end
end
