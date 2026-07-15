class Cadences::ResponseCheckService
  include Cadences::EventLogger

  pattr_initialize [:enrollment!, :step!]

  def perform
    enrollment.reload
    return unless enrollment.waiting_response? || enrollment.pending_agent_call?
    return unless enrollment.current_step == step
    return if enrollment.responded_since_last_template?

    create_call_task_if_needed!
    advance_or_finish!
  end

  private

  delegate :conversation, to: :enrollment

  def definition
    @definition ||= enrollment.step_definition_for(step)
  end

  def create_call_task_if_needed!
    if call_task_needed?
      create_call_task!
    else
      enrollment.update!(status: :active)
    end
  end

  def call_task_needed?
    definition[:creates_call_task] && !CadenceCallTask.exists?(cadence_enrollment_id: enrollment.id, step: step)
  end

  def create_call_task!
    task = CadenceCallTask.create!(
      account_id: enrollment.account_id,
      cadence_enrollment_id: enrollment.id,
      conversation_id: enrollment.conversation_id,
      user_id: conversation.assignee_id,
      step: step,
      status: :pending,
      notified_at: Time.current
    )
    enrollment.update!(status: :pending_agent_call, last_call_task_created_at: Time.current)
    log_cadence_event(enrollment, 'call_task_created', step: step, metadata: { no_agent: task.user_id.blank? })
    notify_agent(task) if task.user_id.present?
  end

  def notify_agent(task)
    NotificationBuilder.new(
      notification_type: 'cadence_call_task',
      user: task.user,
      account: enrollment.account,
      primary_actor: conversation
    ).perform
  end

  def advance_or_finish!
    next_definition = enrollment.step_definition_for(step + 1)
    next_definition.nil? ? finish_cadence! : schedule_next_step!(next_definition)
  end

  def finish_cadence!
    enrollment.update!(status: :cold, stopped_reason: 'no_response_after_cadence')
    log_cadence_event(enrollment, 'cadence_marked_cold', step: step)
  end

  def schedule_next_step!(next_definition)
    run_at = Cadences::ScheduleCalculator.new(enrollment: enrollment, definition: next_definition).next_run_at
    enrollment.update!(next_action_at: run_at)
    Cadences::AdvanceJob.set(wait_until: run_at).perform_later(enrollment.id)
  end
end
