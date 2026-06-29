class AutoAssignment::ZohoOwnerResolver
  def initialize(conversation)
    @conversation = conversation
    @account      = conversation.account
  end

  # Returns the Chatwoot User that owns this contact in Zoho CRM,
  # or nil if Zoho is not configured, the contact has no email,
  # the record is not found, or the owner is not a member of the inbox.
  def resolve
    return nil unless zoho_hook

    email = @conversation.contact.email.presence
    return nil if email.blank?

    record = find_in_zoho(email)
    return nil unless record

    owner_email = record.dig('Owner', 'email').presence
    return nil if owner_email.blank?

    inbox_member_user(owner_email)
  end

  private

  def zoho_hook
    @zoho_hook ||= Integrations::Hook.find_by(
      account: @account,
      app_id: 'zoho_crm',
      status: 'enabled'
    )
  end

  # Searches Leads first, then Contacts.
  def find_in_zoho(email)
    leads = Crm::Zoho::Api::LeadsClient.new(zoho_hook).search(email: email)
    return leads.first if leads.any?

    contacts = Crm::Zoho::Api::ContactsClient.new(zoho_hook).search(email: email)
    contacts.first
  rescue StandardError => e
    Rails.logger.error(
      "[ZohoOwnerResolver] Zoho search failed conv=#{@conversation.id}: #{e.message}"
    )
    nil
  end

  # Only return the user if they are actually a member of the conversation's inbox.
  def inbox_member_user(owner_email)
    user = @account.users.find_by(email: owner_email)
    return nil unless user
    return nil unless @conversation.inbox.inbox_members.exists?(user_id: user.id)

    user
  end
end
