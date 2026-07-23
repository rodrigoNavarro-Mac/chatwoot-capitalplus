class Cadences::EligibilityChecker
  pattr_initialize [:conversation!]

  ELIGIBLE_STATUSES = %w[open pending].freeze

  def eligible?
    whatsapp_inbox? && feature_enabled? && conversation_active? && contact_reachable?
  end

  private

  delegate :inbox, :contact, :account, to: :conversation

  def whatsapp_inbox?
    inbox.inbox_type == 'Whatsapp'
  end

  def feature_enabled?
    account.feature_enabled?(:whatsapp_cadences)
  end

  def conversation_active?
    ELIGIBLE_STATUSES.include?(conversation.status) && contact.present? && !contact.blocked?
  end

  def contact_reachable?
    contact.phone_number.present? && contact.additional_attributes['wa_valid'] != false
  end
end
