# Cliente para el módulo estándar "Products" de Zoho CRM — en esta cuenta representa el catálogo
# de lotes/unidades disponibles (reutilizable entre varios Deals), a diferencia de los campos de
# cotización que antes vivían solo en el Deal. Mismo patrón que DealsClient/LeadsClient.
#
# No se asume el nombre exacto de los campos custom de superficie/precio — se devuelve el registro
# completo tal cual lo entrega Zoho y es el llamador (Quotes::GenerateFromProductService) quien
# intenta mapear las llaves conocidas, dejando el resto disponible para edición manual. "Desarrollo"
# sí está confirmado (Pick List) porque el flujo de selección filtra por él antes de buscar el lote.
class Crm::Zoho::Api::ProductsClient < Crm::Zoho::Api::BaseClient
  # Campos confirmados contra el esquema real de Products de esta cuenta (2026-09-24) —
  # explícitos porque /search sin `fields` no garantiza traer campos custom (mismo problema que
  # documenta Crm::Zoho::Api::DealsClient#search_by_criteria). "Colometria" es un Lookup (no un
  # string simple): Zoho lo devuelve como {id:, name:}.
  SEARCH_FIELDS = %w[Product_Name Desarrollo m2 x_m2_estimado Colometria Fecha_de_entrega Apartado Bloqueado].freeze

  # `word`/`desarrollo` son opcionales pero al menos uno debe venir — filtrar solo por desarrollo
  # (sin texto) lista todos los lotes de ese desarrollo, que es el flujo principal: primero elegir
  # el desarrollo, luego el lote dentro de él.
  def search(word: nil, desarrollo: nil, page: 1, per_page: 100)
    criteria = build_criteria(word: word, desarrollo: desarrollo)
    return [] if criteria.blank?

    response = get('Products/search', criteria: criteria, fields: SEARCH_FIELDS.join(','), page: page, per_page: per_page)
    response.is_a?(Hash) ? Array(response['data']) : []
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    return [] if e.code == 204

    raise
  end

  # Valores del Pick List "Desarrollo" configurados en Zoho — mismo patrón que
  # Api::V1::Accounts::Integrations::ZohoCrmController#fetch_stage_options.
  def desarrollos
    field = find_field('Desarrollo')
    return [] unless field

    Array(field['pick_list_values']).filter_map do |v|
      next unless v.is_a?(Hash)

      v['display_value'].presence || v['actual_value'].presence
    end
  end

  def find(zoho_id, fields: nil)
    params = fields.present? ? { fields: fields.join(',') } : {}
    response = get("Products/#{zoho_id}", params)
    response.is_a?(Hash) ? response.dig('data', 0) : nil
  rescue Crm::Zoho::Api::BaseClient::ApiError
    nil
  end

  private

  def find_field(api_name)
    response = get('settings/fields', module: 'Products')
    fields = Array(response.is_a?(Hash) ? response['fields'] : nil)
    fields.find { |f| f.is_a?(Hash) && f['api_name'] == api_name }
  end

  def build_criteria(word:, desarrollo:)
    clauses = []
    clauses << "(Desarrollo:equals:#{desarrollo})" if desarrollo.present?
    clauses << "(Product_Name:contains:#{word})" if word.present?
    return nil if clauses.empty?

    clauses.join('and')
  end
end
