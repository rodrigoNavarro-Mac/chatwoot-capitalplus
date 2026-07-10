class Cadences::Analytics::AgentsBuilder < Cadences::Analytics::BaseBuilder
  def build
    agent_ids.map { |user_id| agent_metrics(user_id) }
  end

  private

  def agent_ids
    @agent_ids ||= enrollment_scope.where.not(assignee_id: nil).distinct.pluck(:assignee_id)
  end

  def agent_metrics(user_id)
    scope = enrollment_scope.where(assignee_id: user_id)
    tasks = call_task_scope.where(user_id: user_id)
    completed_tasks = tasks.completed

    {
      user_id: user_id,
      user_name: User.find_by(id: user_id)&.name,
      leads_in_cadence: scope.count,
      responses: scope.where(status: RESPONDED_STATUSES).count,
      call_tasks_created: tasks.count,
      calls_completed: completed_tasks.count,
      calls_pending: tasks.pending.count,
      call_compliance_rate: safe_rate(completed_tasks.count, tasks.count),
      avg_time_to_call_seconds: average_seconds(completed_tasks.pluck(:notified_at, :completed_at)),
      recovered_count: scope.recovered.count,
      cold_count: scope.cold.count
    }
  end
end
