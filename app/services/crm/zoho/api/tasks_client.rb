class Crm::Zoho::Api::TasksClient < Crm::Zoho::Api::BaseClient
  # El Owner de un Task en Zoho acepta email como identificador alterno al crear (igual que
  # otros campos de lookup a usuario); si el email no matchea a ningún usuario de Zoho, el
  # Task simplemente queda sin Owner explícito (hereda el dueño del registro padre).
  def create(zoho_id:, zoho_module:, subject:, details: {})
    data = {
      Subject: subject,
      Status: 'Not Started',
      '$se_module': zoho_module,
      Parent_Id: zoho_id
    }
    data[:Due_Date] = details[:due_date].iso8601 if details[:due_date].present?
    data[:Description] = details[:description] if details[:description].present?
    data[:Owner] = { email: details[:owner_email] } if details[:owner_email].present?

    post('Tasks', { data: [data] })
  end

  def list(zoho_id:, zoho_module:, per_page: 10)
    response = get("#{zoho_module}/#{zoho_id}/Tasks", per_page: per_page, sort_by: 'Created_Time', sort_order: 'desc')
    response.is_a?(Hash) ? Array(response['data']) : []
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    return [] if e.code == 204

    raise
  end
end
