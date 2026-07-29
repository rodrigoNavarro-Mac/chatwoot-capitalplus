# Fusiona dos conversaciones duplicadas del mismo contacto (ej. generadas por un contact_inbox
# mismatch, ver Whatsapp::IncomingMessageBaseService#set_conversation): mueve los mensajes de
# la conversación "mergee" a la "base" y elimina la duplicada. Sigue el mismo patrón que
# ContactMergeAction (app/actions/contact_merge_action.rb).
class ConversationMergeAction
  include Events::Types
  pattr_initialize [:account!, :base_conversation!, :mergee_conversation!]

  def perform
    return @base_conversation if base_conversation.id == mergee_conversation.id

    ActiveRecord::Base.transaction do
      validate_conversations
      merge_messages
      merge_cadence_enrollment
      remove_mergee_conversation
    end
    notify_conversation_updated
    @base_conversation
  end

  private

  def validate_conversations
    unless belongs_to_account?(@base_conversation) && belongs_to_account?(@mergee_conversation)
      raise StandardError,
            'conversation does not belong to the account'
    end
    raise StandardError, 'conversations must belong to the same contact' if @base_conversation.contact_id != @mergee_conversation.contact_id
  end

  def belongs_to_account?(conversation)
    @account.id == conversation.account_id
  end

  def merge_messages
    Message.where(conversation_id: @mergee_conversation.id).update(conversation_id: @base_conversation.id)
  end

  # CadenceEnrollment#conversation_id es unique, así que no se puede simplemente reasignar si
  # ambas conversaciones tienen uno — en ese caso el de la base gana y el de la mergee se
  # destruye junto con su conversación (dependent: :destroy), como cualquier otro dato
  # secundario de la conversación duplicada (mentions, csat, etc.). Solo se transfiere el
  # enrollment cuando la base no tiene uno propio, para no perder ese historial/estado.
  def merge_cadence_enrollment
    mergee_enrollment = @mergee_conversation.cadence_enrollment
    return if mergee_enrollment.blank? || @base_conversation.cadence_enrollment.present?

    mergee_enrollment.update!(conversation_id: @base_conversation.id)
  end

  def remove_mergee_conversation
    @mergee_conversation.reload.destroy!
    @base_conversation.update!(last_activity_at: Time.current)
  end

  def notify_conversation_updated
    Rails.configuration.dispatcher.dispatch(
      CONVERSATION_UPDATED, Time.zone.now, conversation: @base_conversation.reload,
                                           notifiable_assignee_change: false, changed_attributes: nil, performed_by: nil
    )
  end
end
