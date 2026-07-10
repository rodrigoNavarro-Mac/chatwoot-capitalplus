class Cadences::EligibilityChecker
  pattr_initialize [:conversation!]

  def eligible?
    whatsapp_inbox? && feature_enabled? && conversation_open? && assignee? && contact_reachable?
  end

  private

  delegate :inbox, :contact, :account, to: :conversation

  def whatsapp_inbox?
    inbox.inbox_type == 'Whatsapp'
  end

  def feature_enabled?
    account.feature_enabled?(:whatsapp_cadences)
  end

  def conversation_open?
    conversation.status == 'open' && contact.present? && !contact.blocked?
  end

  def assignee?
    conversation.assignee_id.present?
  end

  def contact_reachable?
    contact.phone_number.present? && contact.additional_attributes['wa_valid'] != false
  end
end
