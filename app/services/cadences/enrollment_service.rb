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
    Cadences::AdvanceJob.perform_later(enrollment.id)
    enrollment
  end

  private

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
