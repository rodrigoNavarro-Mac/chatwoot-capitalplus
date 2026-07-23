# Contraparte en background del rake task cadences:enroll_past_leads, disparable desde el
# dashboard (botón "Enroll past leads" en la pantalla de Cadencias). Recorre las conversaciones
# de WhatsApp de la cuenta que todavía no tienen CadenceEnrollment y usa
# Cadences::EnrollConversationService (mismo punto de entrada que el flujo en vivo) para
# engancharlas: primero intenta retomar en el paso que corresponde a la última plantilla que
# ya recibieron, y si esa plantilla no es parte de la cadencia activa (ej. el disparador inicial
# de Zoho antes de que existiera cadencia configurada), cae a un enrollment fresco en el paso 0.
# A diferencia del flujo en vivo, no hace ese fallback para no_template_sent: sin ningún
# disparador reciente que lo justifique, no tiene sentido mandarle una plantilla nueva en frío a
# una conversación que nunca tuvo contacto por WhatsApp. Idempotente: una conversación ya
# enrolada se salta.
class Cadences::EnrollPastLeadsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(account_id, inbox_id: nil)
    account = Account.find_by(id: account_id)
    return unless account

    counts = Hash.new(0)
    conversations_scope(account, inbox_id).find_each do |conversation|
      result = Cadences::EnrollConversationService.new(conversation: conversation, fresh_enroll_reasons: %w[no_matching_step]).call
      counts[result.status] += 1
    rescue StandardError => e
      counts[:error] += 1
      Rails.logger.error("[Cadences::EnrollPastLeadsJob] conversation=#{conversation.id} error=#{e.message}")
    end

    Rails.logger.info(
      "[Cadences::EnrollPastLeadsJob] account=#{account_id} inbox=#{inbox_id || 'all'} done. " \
      "#{counts.map { |status, n| "#{status}=#{n}" }.join(' ')}"
    )
  end

  private

  def conversations_scope(account, inbox_id)
    scope = account.conversations.joins(:inbox)
                   .where(inboxes: { channel_type: 'Channel::Whatsapp' })
                   .where.not(id: account.cadence_enrollments.select(:conversation_id))
    scope = scope.where(inbox_id: inbox_id) if inbox_id.present?
    scope
  end
end
