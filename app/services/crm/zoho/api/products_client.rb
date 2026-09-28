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

  # Tope de páginas a recorrer cuando se filtra por texto (ver más abajo) — evita jalar el
  # catálogo completo de un desarrollo enorme, manteniendo la búsqueda rápida.
  WORD_SEARCH_MAX_PAGES = 5
  WORD_SEARCH_PAGE_SIZE = 200
  WORD_SEARCH_MAX_RESULTS = 50

  # `word`/`desarrollo` son opcionales pero al menos uno debe venir — filtrar solo por desarrollo
  # (sin texto) lista todos los lotes de ese desarrollo, que es el flujo principal: primero elegir
  # el desarrollo, luego el lote dentro de él.
  #
  # El filtro por texto NO usa el criteria `Product_Name:contains` de Zoho: ese operador busca por
  # token completo y falla con búsquedas parciales o puramente numéricas (ej. escribir "46" no
  # encuentra "46 PRIV. KRAKATOA"). En vez de eso, se trae el catálogo del desarrollo (paginado) y
  # se filtra por substring en Ruby, que sí encuentra cualquier coincidencia parcial.
  def search(word: nil, desarrollo: nil, page: 1, per_page: 100)
    return search_by_word(word: word, desarrollo: desarrollo) if word.present?

    criteria = build_criteria(desarrollo: desarrollo)
    return [] if criteria.blank?

    fetch_page(criteria: criteria, page: page, per_page: per_page)
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

  # Recorre el catálogo del desarrollo página por página (hasta WORD_SEARCH_MAX_PAGES) filtrando
  # por substring case-insensitive en Product_Name — se detiene apenas junta WORD_SEARCH_MAX_RESULTS
  # coincidencias o se acaban las páginas.
  def search_by_word(word:, desarrollo:)
    criteria = build_criteria(desarrollo: desarrollo)
    return [] if criteria.blank?

    needle = word.strip.downcase
    matches = []

    WORD_SEARCH_MAX_PAGES.times do |i|
      page_records = fetch_page(criteria: criteria, page: i + 1, per_page: WORD_SEARCH_PAGE_SIZE)
      matches.concat(page_records.select { |record| record['Product_Name'].to_s.downcase.include?(needle) })
      break if page_records.size < WORD_SEARCH_PAGE_SIZE || matches.size >= WORD_SEARCH_MAX_RESULTS
    end

    matches.first(WORD_SEARCH_MAX_RESULTS)
  end

  def fetch_page(criteria:, page:, per_page:)
    response = get('Products/search', criteria: criteria, fields: SEARCH_FIELDS.join(','), page: page, per_page: per_page)
    response.is_a?(Hash) ? Array(response['data']) : []
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    return [] if e.code == 204

    raise
  end

  def build_criteria(desarrollo:)
    return nil if desarrollo.blank?

    "(Desarrollo:equals:#{desarrollo})"
  end
end
