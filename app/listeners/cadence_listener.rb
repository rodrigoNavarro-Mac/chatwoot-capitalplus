class CadenceListener < BaseListener
  def assignee_changed(event)
    conversation = extract_conversation_and_account(event)[0]
    return if conversation.assignee_id.blank?

    Cadences::EnrollmentService.new(conversation: conversation).enroll!
  end

  def message_created(event)
    message = extract_message_and_account(event)[0]
    return unless message.incoming?

    enrollment = CadenceEnrollment.in_progress.find_by(conversation_id: message.conversation_id)
    return unless enrollment

    Cadences::PauseOnResponseService.new(enrollment: enrollment, message: message).perform
  end
end
