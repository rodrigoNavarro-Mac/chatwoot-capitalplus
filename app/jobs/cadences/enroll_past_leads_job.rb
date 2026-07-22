# Contraparte en background del rake task cadences:enroll_past_leads, disparable desde el
# dashboard (botón "Enroll past leads" en la pantalla de Cadencias). Recorre las conversaciones
# de WhatsApp de la cuenta que todavía no tienen CadenceEnrollment y usa
# Cadences::PastLeadEnrollmentService para engancharlas en el paso que corresponde a la última
# plantilla que ya recibieron (o step 0 si nunca recibieron una). Idempotente: una conversación
# ya enrolada se salta.
class Cadences::EnrollPastLeadsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(account_id, inbox_id: nil)
    account = Account.find_by(id: account_id)
    return unless account

    counts = Hash.new(0)
    conversations_scope(account, inbox_id).find_each do |conversation|
      result = Cadences::PastLeadEnrollmentService.new(conversation: conversation).call
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
