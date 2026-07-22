# Punto de entrada compartido para enganchar una conversación en cadencia desde cualquier
# disparador (CadenceListener#assignee_changed, Crm::Zoho::SendInitialTemplateService): intenta
# primero Cadences::PastLeadEnrollmentService (retoma en el paso que corresponde a una plantilla
# ya enviada fuera de la cadencia) y, si no aplica, cae a Cadences::EnrollmentService (lead nuevo,
# arranca en el paso 0).
class Cadences::EnrollConversationService
  pattr_initialize [:conversation!]

  def call
    result = Cadences::PastLeadEnrollmentService.new(conversation: conversation).call
    return if result.status == :enrolled
    return unless %w[no_template_sent no_matching_step].include?(result.detail)

    Cadences::EnrollmentService.new(conversation: conversation).enroll!
  rescue StandardError => e
    Rails.logger.error("[Cadences::EnrollConversationService] conversation=#{conversation.id} error=#{e.message}")
  end
end
