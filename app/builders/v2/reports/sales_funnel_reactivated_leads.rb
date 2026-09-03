# Separa, dentro de los leads con zoho_id vinculado, los "nuevos del periodo" (zoho_created_at
# dentro del rango, o todavía sin cachear) de los "reactivados" (zoho_created_at cacheado y ANTERIOR
# al rango) — separado de V2::Reports::SalesFunnelBuilder solo para no pasar su límite de tamaño de
# clase, mismo criterio ya usado con SalesFunnelDealActivity/ZohoLeadsMetrics.
#
# Sin esto, la primera conversación de Chatwoot de un lead reactivado (ej. campaña de reactivación a
# leads viejos vía CSV) se contaba igual que un lead nuevo del periodo, aunque el lead real de Zoho
# llevara meses (caso real detectado 2026-09-03: 278 vs 211 leads de un desarrollo en agosto, 53 de
# la diferencia eran una sola campaña de reactivación del 2026-08-26). Los reactivados NO se
# descartan del reporte: el frontend los pinta aparte (badge/color distinto, ver FunnelStageMeter.vue)
# en vez de desaparecer sin explicación del embudo.
class V2::Reports::SalesFunnelReactivatedLeads
  CREATED_WITHIN_RANGE_SQL = <<~SQL.squish.freeze
    additional_attributes -> 'external' ->> 'zoho_created_at' IS NULL
    OR (
      (additional_attributes -> 'external' ->> 'zoho_created_at')::timestamptz >= ?
      AND (additional_attributes -> 'external' ->> 'zoho_created_at')::timestamptz < ?
    )
  SQL

  def initialize(range:)
    @range = range
  end

  # [nuevos, reactivados] — `zoho_created_at` (el Created_Time real de Zoho) se cachea en
  # Crm::Zoho::ContactFinderService al vincular el contacto; si todavía no está cacheado (contacto
  # vinculado antes de que existiera este campo, o backfill parcial vía
  # lib/tasks/backfill_zoho_lead_created_at.rake) se sigue tratando como "nuevo" — el mismo
  # comportamiento de antes de este cambio, para no excluir por error leads genuinamente nuevos
  # mientras el backfill no ha llegado a ellos.
  def partition(pairs)
    return [pairs, []] if range.blank? || pairs.empty?

    new_ids = Contact.where(id: pairs.map(&:last)).where(CREATED_WITHIN_RANGE_SQL, range.begin, range.end).pluck(:id).to_set
    pairs.partition { |(_conversation_id, contact_id)| new_ids.include?(contact_id) }
  end

  private

  attr_reader :range
end
