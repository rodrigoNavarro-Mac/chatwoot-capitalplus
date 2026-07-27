class Cadences::EnrollmentService
  include Cadences::EventLogger

  pattr_initialize [:conversation!]

  def enroll!
    return if CadenceEnrollment.exists?(conversation_id: conversation.id)
    return unless Cadences::EligibilityChecker.new(conversation: conversation).eligible?

    cadence_definition = Cadences::CadenceDefinitionResolver.new(conversation: conversation).resolve
    return if cadence_definition.blank?

    snapshot = Cadences::StepsRepository.snapshot_for(cadence_definition)
    return if snapshot.blank?

    enrollment = CadenceEnrollment.create!(enrollment_attributes(cadence_definition, snapshot))

    log_cadence_event(enrollment, 'cadence_started', step: 0)
    schedule_first_step!(enrollment)
    enrollment
  end

  private

  # El paso 1 puede tener su propio schedule_type (ej. "day_offset_at_time": 1 dia despues a
  # cierta hora), igual que cualquier otro paso — no siempre es "immediate". ScheduleCalculator
  # ya usa enrollment.created_at como anchor cuando todavia no se mando ninguna plantilla, asi
  # que sirve tal cual para calcular el primer envio tambien.
  def schedule_first_step!(enrollment)
    first_step = enrollment.step_definition_for(1)
    run_at = Cadences::ScheduleCalculator.new(enrollment: enrollment, definition: first_step).next_run_at
    enrollment.update!(next_action_at: run_at)
    Cadences::AdvanceJob.set(wait_until: run_at).perform_later(enrollment.id)
  end

  def enrollment_attributes(cadence_definition, snapshot)
    {
      account_id: conversation.account_id,
      conversation_id: conversation.id,
      contact_id: conversation.contact_id,
      inbox_id: conversation.inbox_id,
      cadence_definition_id: cadence_definition.id,
      assignee_id: conversation.assignee_id,
      status: :active,
      current_step: 0,
      steps_snapshot: snapshot
    }
  end
end
