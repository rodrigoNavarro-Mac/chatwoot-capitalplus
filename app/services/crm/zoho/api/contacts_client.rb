class Crm::Zoho::Api::ContactsClient < Crm::Zoho::Api::BaseClient
  def search(email: nil, phone: nil)
    value = email.presence || phone.presence
    return [] if value.blank?

    response = get('Contacts/search', word: value)
    response.is_a?(Hash) ? Array(response['data']) : []
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    return [] if e.code == 204
    raise
  end

  def create(data)
    response = post('Contacts', { data: [data] })
    response.dig('data', 0, 'details', 'id')
  end

  def update(zoho_id, data)
    put("Contacts/#{zoho_id}", { data: [data] })
  end

  # `fields` es obligatorio para que Zoho devuelva el registro completo (sin él, la API
  # "Get Specific Record" omite campos estándar como Title/Account_Name aunque tengan valor).
  FIND_FIELDS = 'First_Name,Last_Name,Email,Phone,Mobile,Title,Account_Name,Owner'.freeze

  def find(zoho_id)
    response = get("Contacts/#{zoho_id}", fields: FIND_FIELDS)
    response.is_a?(Hash) ? response.dig('data', 0) : nil
  rescue Crm::Zoho::Api::BaseClient::ApiError
    nil
  end
end
