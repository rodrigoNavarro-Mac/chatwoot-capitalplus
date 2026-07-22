class Crm::Zoho::Api::LeadsClient < Crm::Zoho::Api::BaseClient
  def search(email: nil, phone: nil)
    criteria = search_criteria(email: email, phone: phone)
    return [] if criteria.blank?

    response = get('Leads/search', criteria: criteria)
    response.is_a?(Hash) ? Array(response['data']) : []
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    return [] if e.code == 204
    raise
  end

  def create(data)
    response = post('Leads', { data: [data] })
    response.dig('data', 0, 'details', 'id')
  end

  def update(zoho_id, data)
    put("Leads/#{zoho_id}", { data: [data] })
  end

  def find(zoho_id)
    response = get("Leads/#{zoho_id}")
    response.is_a?(Hash) ? response.dig('data', 0) : nil
  rescue Crm::Zoho::Api::BaseClient::ApiError
    nil
  end
end
