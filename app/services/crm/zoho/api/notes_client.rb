class Crm::Zoho::Api::NotesClient < Crm::Zoho::Api::BaseClient
  # CONFIRMADO en producción 2026-09-01: Zoho rechaza Parent_Id como string plano con
  # "INVALID_DATA — expected_data_type: jsonobject" — en esta org/versión de la API, el campo
  # espera un objeto de lookup ({"id": "..."}) igual que cualquier otro campo de relación, no el ID
  # crudo. Confirmado con notas reales fallando contra el módulo Deals.
  def create(zoho_id:, zoho_module:, title:, content:)
    post('Notes', {
           data: [{
             Note_Title: title,
             Note_Content: content,
             '$se_module': zoho_module,
             Parent_Id: { id: zoho_id }
           }]
         })
  end

  def list(zoho_id:, zoho_module:, per_page: 5)
    response = get("#{zoho_module}/#{zoho_id}/Notes", per_page: per_page, sort_by: 'Created_Time', sort_order: 'desc')
    response.is_a?(Hash) ? Array(response['data']) : []
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    return [] if e.code == 204
    raise
  end
end
