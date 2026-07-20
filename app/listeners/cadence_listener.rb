class CadenceListener < BaseListener
  def assignee_changed(event)
    conversation = extract_conversation_and_account(event)[0]
    return if conversation.assignee_id.blank?

    # Si la conversación ya tiene una plantilla enviada fuera de cadencia (manual desde el
    # composer/API, o desde Crm::Zoho::SendInitialTemplateService), engancha el enrollment en el
    # paso que corresponde a esa plantilla en vez de repetirla desde el paso 0. Si no hay
    # plantilla previa que matchee, cae al enrollment normal (lead nuevo sin mensajes).
    result = Cadences::PastLeadEnrollmentService.new(conversation: conversation).call
    return if result.status == :enrolled
    return unless %w[no_template_sent no_matching_step].include?(result.detail)

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
