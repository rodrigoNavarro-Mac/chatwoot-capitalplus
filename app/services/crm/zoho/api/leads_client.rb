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
  #
  # `converted` se deja en 'false' por default (mismo comportamiento de siempre) — Zoho excluye los
  # leads ya convertidos a Deal tanto de /search sin este parámetro como de GET Leads/{id} (#find),
  # así que cualquier caller que necesite resolver un lead que pudo haberse convertido (ej. el
  # backfill de zoho_created_at, ver #find_any) debe pasar 'both' explícitamente.
  def search_by_criteria(criteria, page: 1, per_page: 200, converted: 'false')
    response = get('Leads/search', criteria: criteria, page: page, per_page: per_page, converted: converted)
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

  # Igual que #find, pero también resuelve leads ya CONVERTIDOS a Deal — #find (GET Leads/{id}) los
  # devuelve vacío en cuanto se convierten (confirmado 2026-09-03 contra la API real: un lead
  # convertido deja de existir para ese endpoint), así que hay que ir por /search con
  # converted: 'both'. Usado por el backfill de zoho_created_at (lib/tasks/backfill_zoho_lead_created_at.rake)
  # para no tratar como "borrado" un lead que en realidad solo avanzó a Deal.
  def find_any(zoho_id)
    result = search_by_criteria("(id:equals:#{zoho_id})", per_page: 1, converted: 'both')
    result[:data].first
  end
end
