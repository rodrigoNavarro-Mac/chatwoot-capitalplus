class Cadences::Analytics::StepsBuilder < Cadences::Analytics::BaseBuilder
  def build
    Cadences::StepDefinitions::STEPS.map { |definition| step_metrics(definition) }
  end

  private

  def step_metrics(definition)
    step = definition[:step]
    sent = event_scope.where(event_type: 'template_sent', step: step).count
    responded = responded_count(step)

    {
      step: step,
      template_key: definition[:template_key],
      sent: sent,
      responded: responded,
      response_rate: safe_rate(responded, sent),
      no_response: sent - responded,
      avg_response_time_seconds: avg_response_time(step),
      advanced_to_next_step: enrollment_scope.where('current_step > ?', step).count
    }.merge(call_task_metrics(step))
  end

  def responded_count(step)
    enrollment_scope.where(current_step: step, status: RESPONDED_STATUSES).count
  end

  def call_task_metrics(step)
    call_tasks = call_task_scope.where(step: step)
    required = call_tasks.count
    completed = call_tasks.completed.count

    { call_tasks_required: required, call_tasks_completed: completed, call_compliance_rate: safe_rate(completed, required) }
  end

  def avg_response_time(step)
    pairs = enrollment_scope.where(current_step: step, status: RESPONDED_STATUSES).pluck(:last_template_sent_at, :last_lead_response_at)
    average_seconds(pairs)
  end
end
