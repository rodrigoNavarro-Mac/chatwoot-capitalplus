class Crm::Zoho::ProcessorService < Crm::BaseProcessorService
  def self.crm_name
    'zoho'
  end

  def initialize(hook)
    super(hook)
    @enable_conversation_note = hook.settings['enable_conversation_note']
    @enable_transcript_note = hook.settings['enable_transcript_note']
    @finder = Crm::Zoho::ContactFinderService.new(hook)
    @notes_client = Crm::Zoho::Api::NotesClient.new(hook)
    @leads_client = Crm::Zoho::Api::LeadsClient.new(hook)
    @contacts_client = Crm::Zoho::Api::ContactsClient.new(hook)
  end

  def handle_contact_created(event_data)
    handle_contact(event_data[:contact])
  end

  def handle_contact_updated(event_data)
    handle_contact(event_data[:contact])
  end

  def handle_contact(contact)
    contact.reload
    unless identifiable_contact?(contact)
      Rails.logger.info("[ZOHO CRM] Contact ##{contact.id} not identifiable, skipping")
      return
    end

    result = @finder.find_or_create(contact)
    sync_contact_to_zoho(contact, result)
    ensure_conversation_link_notes(contact, result)
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    log_api_error('handle_contact', contact.id, e)
  rescue StandardError => e
    log_error('handle_contact', contact.id, e)
    raise
  end

  def handle_conversation_created(event_data)
    conversation = event_data[:conversation]
    contact = conversation.contact
    contact.reload

    unless identifiable_contact?(contact)
      Rails.logger.info("[ZOHO CRM] Conversation ##{conversation.id}: contact not identifiable, skipping")
      return
    end

    result = @finder.find_or_create(contact)
    enrich_chatwoot_contact(contact, result)
    import_recent_zoho_notes(contact, result)

    create_zoho_note(
      result,
      title: "Conversación ##{conversation.display_id}",
      content: Crm::Zoho::Mappers::ConversationMapper.conversation_note(conversation)
    )
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    log_api_error('handle_conversation_created', conversation.id, e)
  rescue StandardError => e
    log_error('handle_conversation_created', conversation.id, e)
    raise
  end

  def handle_conversation_resolved(event_data)
    conversation = event_data[:conversation]
    return unless @enable_transcript_note
    return unless conversation.status == 'resolved'

    contact = conversation.contact
    contact.reload

    unless identifiable_contact?(contact)
      Rails.logger.info("[ZOHO CRM] Resolved conversation ##{conversation.id}: contact not identifiable, skipping")
      return
    end

    result = @finder.find_or_create(contact)
    create_zoho_note(
      result,
      title: "Transcript ##{conversation.display_id}",
      content: Crm::Zoho::Mappers::ConversationMapper.transcript_note(conversation)
    )
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    log_api_error('handle_conversation_resolved', conversation.id, e)
  rescue StandardError => e
    log_error('handle_conversation_resolved', conversation.id, e)
    raise
  end

  private

  def sync_contact_to_zoho(contact, result)
    data = Crm::Zoho::Mappers::ContactMapper.map(contact, module_name: result[:zoho_module])
    if result[:zoho_module] == 'Leads'
      @leads_client.update(result[:zoho_id], data)
    else
      @contacts_client.update(result[:zoho_id], data)
    end
  end

  def ensure_conversation_link_notes(contact, result)
    frontend_url = ENV['FRONTEND_URL'].presence
    return unless frontend_url

    conversations = contact.conversations
                           .where(status: [Conversation.statuses[:open], Conversation.statuses[:pending]])
                           .order(created_at: :desc)
                           .limit(5)
    return if conversations.empty?

    existing_notes = @notes_client.list(zoho_id: result[:zoho_id], zoho_module: result[:zoho_module])
    existing_contents = existing_notes.map { |n| n['Note_Content'].to_s }

    conversations.each do |conversation|
      chat_url = Crm::Zoho::Mappers::ConversationMapper.conversation_note(conversation)
      next if chat_url.blank?
      next if existing_contents.any? { |c| c.include?(chat_url) }

      create_zoho_note(
        result,
        title: "Conversación ##{conversation.display_id}",
        content: chat_url
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[ZOHO CRM] Failed to ensure conversation links for contact ##{contact.id}: #{e.message}")
  end

  def enrich_chatwoot_contact(contact, result)
    record = result[:record] || @finder.fetch_record(contact)
    return if record.blank?

    updates = {}
    updates[:company_name] = record['Company'] if record['Company'].present? && contact.company_name.blank?

    return if updates.empty?

    contact.update!(updates)
  rescue StandardError => e
    Rails.logger.warn("[ZOHO CRM] Failed to enrich contact ##{contact.id}: #{e.message}")
  end

  def import_recent_zoho_notes(contact, result)
    notes = @notes_client.list(zoho_id: result[:zoho_id], zoho_module: result[:zoho_module], per_page: 3)
    return if notes.empty?

    notes.each do |note|
      content = "[Zoho CRM] #{note['Note_Title']}\n#{note['Note_Content']}"
      Note.find_or_create_by!(
        account: @account,
        contact: contact,
        content: content
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[ZOHO CRM] Failed to import notes for contact ##{contact.id}: #{e.message}")
  end

  def create_zoho_note(result, title:, content:)
    @notes_client.create(
      zoho_id: result[:zoho_id],
      zoho_module: result[:zoho_module],
      title: title,
      content: content
    )
  end

  def log_api_error(action, resource_id, error)
    ChatwootExceptionTracker.new(error, account: @account).capture_exception
    Rails.logger.error("[ZOHO CRM] API error in #{action} for ##{resource_id}: #{error.message}")
  end

  def log_error(action, resource_id, error)
    ChatwootExceptionTracker.new(error, account: @account).capture_exception
    Rails.logger.error("[ZOHO CRM] Error in #{action} for ##{resource_id}: #{error.message}")
  end
end
