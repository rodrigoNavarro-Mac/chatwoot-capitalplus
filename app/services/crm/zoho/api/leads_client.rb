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

  # Búsqueda por criteria arbitrario (a diferencia de #search, que arma su propio criteria de
  # email/teléfono) — usado por Crm::Zoho::LeadsForPeriodService para traer todos los leads de un
  # desarrollo en un rango de fechas, paginando (Zoho devuelve máx. 200 registros por página).
  def search_by_criteria(criteria, page: 1, per_page: 200)
    response = get('Leads/search', criteria: criteria, page: page, per_page: per_page)
    data = response.is_a?(Hash) ? Array(response['data']) : []
    more_records = response.is_a?(Hash) ? response.dig('info', 'more_records') || false : false

    { data: data, more_records: more_records }
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    return { data: [], more_records: false } if e.code == 204

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
