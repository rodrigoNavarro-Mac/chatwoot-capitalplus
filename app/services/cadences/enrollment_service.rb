class Cadences::EnrollmentService
  include Cadences::EventLogger

  pattr_initialize [:conversation!]

  def enroll!
    return if CadenceEnrollment.exists?(conversation_id: conversation.id)
    return unless Cadences::EligibilityChecker.new(conversation: conversation).eligible?

    enrollment = CadenceEnrollment.create!(
      account_id: conversation.account_id,
      conversation_id: conversation.id,
      contact_id: conversation.contact_id,
      inbox_id: conversation.inbox_id,
      assignee_id: conversation.assignee_id,
      status: :active,
      current_step: 0
    )

    log_cadence_event(enrollment, 'cadence_started', step: 0)
    Cadences::AdvanceJob.perform_later(enrollment.id)
    enrollment
  end
end
