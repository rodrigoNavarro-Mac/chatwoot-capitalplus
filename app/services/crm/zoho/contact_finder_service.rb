class Crm::Zoho::ContactFinderService
  ZOHO_ID_KEY = 'zoho_id'.freeze
  ZOHO_MODULE_KEY = 'zoho_module'.freeze

  def initialize(hook)
    @hook = hook
    @leads_client = Crm::Zoho::Api::LeadsClient.new(hook)
    @contacts_client = Crm::Zoho::Api::ContactsClient.new(hook)
  end

  # Returns { zoho_id:, zoho_module:, record: } or raises on failure.
  def find_or_create(contact)
    stored = stored_zoho_data(contact)
    return stored if stored.present?

    result = find_in_zoho(contact)
    result ||= create_lead(contact)

    store_zoho_data(contact, result[:zoho_id], result[:zoho_module])
    result
  end

  # Fetches the full record from Zoho using the stored ID.
  def fetch_record(contact)
    data = stored_zoho_data(contact)
    return nil if data.blank?

    client = data[:zoho_module] == 'Leads' ? @leads_client : @contacts_client
    client.find(data[:zoho_id])
  end

  private

  def stored_zoho_data(contact)
    ext = contact.additional_attributes&.dig('external')
    return nil if ext.blank?

    zoho_id = ext[ZOHO_ID_KEY]
    zoho_module = ext[ZOHO_MODULE_KEY].presence || 'Leads'
    return nil if zoho_id.blank?

    { zoho_id: zoho_id, zoho_module: zoho_module }
  end

  def find_in_zoho(contact)
    result = search_leads(contact)
    result ||= search_contacts(contact)
    result
  end

  def search_leads(contact)
    records = @leads_client.search(email: contact.email, phone: contact.phone_number)
    return nil if records.empty?

    { zoho_id: records.first['id'], zoho_module: 'Leads', record: records.first }
  end

  def search_contacts(contact)
    records = @contacts_client.search(email: contact.email, phone: contact.phone_number)
    return nil if records.empty?

    { zoho_id: records.first['id'], zoho_module: 'Contacts', record: records.first }
  end

  def create_lead(contact)
    data = Crm::Zoho::Mappers::ContactMapper.map(contact, module_name: 'Leads')
    zoho_id = @leads_client.create(data)
    raise 'Zoho CRM: create Lead returned no ID' if zoho_id.blank?

    { zoho_id: zoho_id, zoho_module: 'Leads' }
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    duplicate_id = extract_duplicate_id(e)
    raise unless duplicate_id.present?

    Rails.logger.info("[ZOHO CRM] Lead already exists (DUPLICATE_DATA), reusing id=#{duplicate_id} for contact ##{contact.id}")
    { zoho_id: duplicate_id, zoho_module: 'Leads' }
  end

  def extract_duplicate_id(error)
    error.response&.parsed_response&.dig('data', 0, 'details', 'duplicate_record', 'id')
  rescue StandardError
    nil
  end

  def store_zoho_data(contact, zoho_id, zoho_module)
    contact.additional_attributes = {} if contact.additional_attributes.nil?
    contact.additional_attributes['external'] ||= {}
    contact.additional_attributes['external'][ZOHO_ID_KEY] = zoho_id
    contact.additional_attributes['external'][ZOHO_MODULE_KEY] = zoho_module
    contact.save!
  end
end
