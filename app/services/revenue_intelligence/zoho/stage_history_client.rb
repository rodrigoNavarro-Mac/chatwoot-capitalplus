# Cliente del related list nativo `Deals/{id}/Stage_History` de Zoho — hereda Crm::Zoho::Api::
# BaseClient sin modificarlo (mismo patrón que LeadsClient/DealsClient/MeetingsClient), 100%
# aditivo. Único cliente Zoho nuevo de Revenue Intelligence.
#
# Forma del payload confirmada contra la cuenta real de Fuego (no asumida): cada fila trae `id`
# estable, `Stage` (la etapa en la que estuvo el deal), `Moved_To__s` (a qué etapa se movió desde
# ahí — null si es la etapa actual), `Stage_Duration_Calendar_Days` (días que Zoho ya calculó que
# duró en esa etapa — null si es la etapa actual, aún no ha "salido"), y `Modified_Time` (cuándo
# se registró/cerró esa fila). Ver RevenueIntelligence::StageHistoryBuilder para cómo se traduce
# esto a entered_at/exited_at/duration_seconds.
class RevenueIntelligence::Zoho::StageHistoryClient < Crm::Zoho::Api::BaseClient
  FIELDS = %w[id Stage Moved_To__s Stage_Duration_Calendar_Days Modified_Time Amount].freeze

  def list(zoho_deal_id)
    response = get("Deals/#{zoho_deal_id}/Stage_History", fields: FIELDS.join(','))
    response.is_a?(Hash) ? Array(response['data']) : []
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    return [] if e.code == 204

    raise
  end
end
