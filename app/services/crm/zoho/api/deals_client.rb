# Busca el Deal más reciente vinculado a cada contacto, por teléfono/correo, en vez de por el
# id de Zoho que Chatwoot tiene guardado.
#
# Esto es necesario porque el flujo real es: el lead nace como Lead en Zoho, y se convierte a
# Contact ahí mismo cuando agenda una cita (fuera de Chatwoot). Esa conversión crea un Contact
# con un id nuevo en Zoho, pero Chatwoot nunca se entera — additional_attributes.external sigue
# apuntando al Lead original. El teléfono, en cambio, es estable y ya vive en el Contact de
# Chatwoot.
#
# Se implementa en dos pasos con la API REST normal de búsqueda (Contacts/search, Deals/search)
# en vez de COQL: una llamada real contra la cuenta de Zoho de producción confirmó que el token
# OAuth de esta integración no tiene el scope ZohoCRM.coql.READ (401 OAUTH_SCOPE_MISMATCH), y
# COQL no funciona sin ese scope. El endpoint /search sí funciona con los scopes de módulo
# normales, que es justo lo que ya usan LeadsClient/ContactsClient con éxito.
class Crm::Zoho::Api::DealsClient < Crm::Zoho::Api::BaseClient
  # contacts: [{ id:, phone:, email: }, ...] — id es el id del Contact de Chatwoot (no de Zoho).
  # Devuelve { chatwoot_contact_id => { deal_id:, stage:, modified_time: } }.
  def deals_for_contacts(contacts)
    contacts.each_with_object({}) do |contact, result|
      next unless contact[:phone].present? || contact[:email].present?

      zoho_contact_id = resolve_contact_id(contact)
      next unless zoho_contact_id

      deal = find_deal_for(zoho_contact_id)
      result[contact[:id]] = deal if deal
    end
  end

  # Búsqueda por criteria arbitrario (a diferencia de #deals_for_contacts, que arma su propio
  # criteria de un solo contacto) — usado por Crm::Zoho::DealsForPeriodService para traer todos los
  # deals de un desarrollo creados en un rango de fechas, paginando (mismo patrón que
  # Crm::Zoho::Api::LeadsClient#search_by_criteria).
  def search_by_criteria(criteria, page: 1, per_page: 200)
    response = get('Deals/search', criteria: criteria, page: page, per_page: per_page)
    data = response.is_a?(Hash) ? Array(response['data']) : []
    more_records = response.is_a?(Hash) ? response.dig('info', 'more_records') || false : false

    { data: data, more_records: more_records }
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    return { data: [], more_records: false } if e.code == 204

    raise
  end

  private

  def resolve_contact_id(contact)
    criteria = search_criteria(email: contact[:email], phone: contact[:phone])
    return nil if criteria.blank?

    response = get('Contacts/search', criteria: criteria)
    Array(response['data']).first&.dig('id')
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    return nil if e.code == 204

    raise
  end

  def find_deal_for(zoho_contact_id)
    response = get('Deals/search', criteria: "(Contact_Name:equals:#{zoho_contact_id})")
    rows = Array(response['data'])
    return nil if rows.empty?

    best = rows.max_by { |row| row['Modified_Time'].to_s }
    { deal_id: best['id'], stage: best['Stage'], modified_time: best['Modified_Time'] }
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    return nil if e.code == 204

    raise
  end
end
