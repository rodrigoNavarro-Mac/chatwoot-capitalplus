class Crm::Zoho::Api::ContactsClient < Crm::Zoho::Api::BaseClient
  def search(email: nil, phone: nil)
    criteria = search_criteria(email: email, phone: phone)
    return [] if criteria.blank?

    response = get('Contacts/search', criteria: criteria)
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

  def find(zoho_id)
    response = get("Contacts/#{zoho_id}")
    response.is_a?(Hash) ? response.dig('data', 0) : nil
  rescue Crm::Zoho::Api::BaseClient::ApiError
    nil
  end
end
