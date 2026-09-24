# Cliente para el módulo estándar "Products" de Zoho CRM — en esta cuenta representa el catálogo
# de lotes/unidades disponibles (reutilizable entre varios Deals), a diferencia de los campos de
# cotización que antes vivían solo en el Deal. Mismo patrón que DealsClient/LeadsClient.
#
# No se asume el nombre exacto de los campos custom de superficie/precio/desarrollo — se devuelve
# el registro completo tal cual lo entrega Zoho y es el llamador (Quotes::GenerateFromProductService)
# quien intenta mapear las llaves conocidas, dejando el resto disponible para edición manual.
class Crm::Zoho::Api::ProductsClient < Crm::Zoho::Api::BaseClient
  def search(word, page: 1, per_page: 20)
    return [] if word.blank?

    response = get('Products/search', word: word, page: page, per_page: per_page)
    response.is_a?(Hash) ? Array(response['data']) : []
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    return [] if e.code == 204

    raise
  end

  def find(zoho_id, fields: nil)
    params = fields.present? ? { fields: fields.join(',') } : {}
    response = get("Products/#{zoho_id}", params)
    response.is_a?(Hash) ? response.dig('data', 0) : nil
  rescue Crm::Zoho::Api::BaseClient::ApiError
    nil
  end
end
