class Crm::Zoho::InboundWebhookService
  def initialize(account, params)
    @account = account
    @params = params.with_indifferent_access
  end

  def perform
    zoho_module = @params['module']
    event = @params['event']

    case zoho_module
    when 'Leads', 'Contacts'
      handle_record_event(zoho_module, event)
    when 'Notes'
      handle_note_event if event == 'create'
    else
      Rails.logger.info("[ZOHO CRM] Inbound webhook: unsupported module '#{zoho_module}'")
    end
  rescue StandardError => e
    Rails.logger.error("[ZOHO CRM] Inbound webhook error: #{e.message}")
  end

  private

  def handle_record_event(zoho_module, event)
    zoho_id = @params['id']
    return if zoho_id.blank?

    contact = find_chatwoot_contact(zoho_id, zoho_module)

    if contact
      update_chatwoot_contact(contact, zoho_module)
    elsif event == 'create'
      create_chatwoot_contact(zoho_module)
    end
  end

  def handle_note_event
    zoho_id = @params['parent_id'] || @params['Parent_Id']
    zoho_module = @params['parent_module'] || 'Leads'
    return if zoho_id.blank?

    contact = find_chatwoot_contact(zoho_id, zoho_module)
    return if contact.blank?

    title = @params['Note_Title'].presence || 'Nota de Zoho CRM'
    content = @params['Note_Content'].presence || ''
    full_content = "[Zoho CRM] #{title}\n#{content}"

    Note.find_or_create_by!(account: @account, contact: contact, content: full_content)
  end

  def find_chatwoot_contact(zoho_id, zoho_module)
    @account.contacts
            .where("additional_attributes -> 'external' ->> 'zoho_id' = ?", zoho_id.to_s)
            .where("additional_attributes -> 'external' ->> 'zoho_module' = ?", zoho_module)
            .first
  end

  def update_chatwoot_contact(contact, zoho_module)
    updates = {}
    updates[:name] = full_name if full_name.present? && contact.name.blank?
    updates[:email] = @params['Email'] if @params['Email'].present? && contact.email.blank?
    updates[:phone_number] = @params['Phone'] if @params['Phone'].present? && contact.phone_number.blank?
    updates[:company_name] = @params['Company'] if @params['Company'].present? && contact.company_name.blank?

    contact.update!(updates) if updates.any?
  end

  def create_chatwoot_contact(zoho_module)
    return if @params['Email'].blank? && @params['Phone'].blank?

    zoho_id = @params['id']
    contact = @account.contacts.create!(
      name: full_name.presence || @params['Email'],
      email: @params['Email'].presence,
      phone_number: @params['Phone'].presence,
      company_name: @params['Company'].presence,
      additional_attributes: {
        'external' => {
          'zoho_id' => zoho_id,
          'zoho_module' => zoho_module
        }
      }
    )

    Rails.logger.info("[ZOHO CRM] Created Chatwoot contact ##{contact.id} from Zoho #{zoho_module} #{zoho_id}")
  end

  def full_name
    [
      @params['First_Name'].presence,
      @params['Last_Name'].presence
    ].compact.join(' ').presence
  end
end
