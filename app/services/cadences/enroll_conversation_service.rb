# Punto de entrada compartido para enganchar una conversación en cadencia desde cualquier
# disparador (CadenceListener#assignee_changed, Crm::Zoho::SendInitialTemplateService,
# Cadences::EnrollPastLeadsJob): intenta primero Cadences::PastLeadEnrollmentService (retoma en
# el paso que corresponde a una plantilla ya enviada fuera de la cadencia) y, si no aplica, cae a
# Cadences::EnrollmentService (lead nuevo, arranca en el paso 0).
#
# fresh_enroll_reasons controla para cuáles motivos de PastLeadEnrollmentService se activa ese
# fallback. Los disparadores en vivo (asignación de agente, plantilla recién enviada por Zoho)
# tienen un evento concreto que justifica arrancar la cadencia aunque nunca haya habido plantilla
# previa (no_template_sent). El job masivo de leads pasados, en cambio, no tiene ningún disparador
# — solo pasa uno más conservador (solo no_matching_step) para no mandar una plantilla nueva en
# frío a conversaciones que nunca tuvieron ningún contacto por WhatsApp.
class Cadences::EnrollConversationService
  Result = Cadences::PastLeadEnrollmentService::Result
  DEFAULT_FRESH_ENROLL_REASONS = %w[no_template_sent no_matching_step].freeze

  def initialize(conversation:, fresh_enroll_reasons: DEFAULT_FRESH_ENROLL_REASONS)
    @conversation = conversation
    @fresh_enroll_reasons = fresh_enroll_reasons
  end

  attr_reader :conversation, :fresh_enroll_reasons

  def call
    result = Cadences::PastLeadEnrollmentService.new(conversation: conversation).call
    return result if result.status == :enrolled
    return result unless fresh_enroll_reasons.include?(result.detail)

    fresh_enroll(result)
  rescue StandardError => e
    Rails.logger.error("[Cadences::EnrollConversationService] conversation=#{conversation.id} error=#{e.message}")
    Result.new(conversation_id: conversation.id, status: :error, detail: e.message)
  end

  private

  def fresh_enroll(past_lead_result)
    enrollment = Cadences::EnrollmentService.new(conversation: conversation).enroll!
    if enrollment.blank?
      return Result.new(conversation_id: conversation.id, status: :skipped, detail: "fresh_enroll_failed_after_#{past_lead_result.detail}")
    end

    Result.new(conversation_id: conversation.id, status: :enrolled,
               detail: "fresh_step0 cadence_definition=#{enrollment.cadence_definition_id}")
  end
end
