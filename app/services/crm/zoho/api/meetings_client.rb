class Crm::Zoho::Api::MeetingsClient < Crm::Zoho::Api::BaseClient
  # `fields` es obligatorio en la API v7 de Zoho para listados de related records (a diferencia de
  # v2, donde era opcional) — sin él, Zoho responde 400 REQUIRED_PARAM_MISSING. Cubre los campos
  # que consumen tanto el panel de Zoho en el widget de conversación (Event_Title/Start_DateTime/
  # End_DateTime/Venue/Owner) como RevenueIntelligence::SyncZohoMeetingsJob (+ Resultado).
  DEFAULT_FIELDS = %w[Event_Title Start_DateTime End_DateTime Venue Owner Resultado].freeze

  # sort_by solo acepta id/Created_Time/Modified_Time en listados de related records de la API v7
  # (Start_DateTime, válido en v2, ya no lo es — confirmado en producción: 400 INVALID_DATA con
  # supported_values: ["id", "Created_Time", "Modified_Time"]). Modified_Time desc es el proxy más
  # cercano a "más reciente primero" que la API permite aquí.
  def list(zoho_id:, zoho_module:, per_page: 10)
    response = get("#{zoho_module}/#{zoho_id}/Events", per_page: per_page, sort_by: 'Modified_Time', sort_order: 'desc',
                                                       fields: DEFAULT_FIELDS.join(','))
    response.is_a?(Hash) ? Array(response['data']) : []
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    return [] if e.code == 204
    raise
  end
end
