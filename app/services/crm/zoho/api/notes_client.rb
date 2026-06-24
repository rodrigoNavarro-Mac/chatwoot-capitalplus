class Crm::Zoho::Api::NotesClient < Crm::Zoho::Api::BaseClient
  def create(zoho_id:, zoho_module:, title:, content:)
    post('Notes', {
           data: [{
             Note_Title: title,
             Note_Content: content,
             '$se_module': zoho_module,
             Parent_Id: { id: zoho_id, module: zoho_module }
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
