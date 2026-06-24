class Crm::Zoho::Api::MeetingsClient < Crm::Zoho::Api::BaseClient
  def list(zoho_id:, zoho_module:, per_page: 10)
    response = get("#{zoho_module}/#{zoho_id}/Events", per_page: per_page, sort_by: 'Start_DateTime', sort_order: 'desc')
    response.is_a?(Hash) ? Array(response['data']) : []
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    return [] if e.code == 204
    raise
  end
end
