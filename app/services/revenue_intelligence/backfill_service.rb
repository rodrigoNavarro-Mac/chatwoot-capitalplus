# Backfill histórico manual (invocado por lib/tasks/backfill_revenue_intelligence.rake) — NO
# duplica la lógica de sincronización: siembra el cursor de cada RevenueIntelligence::SyncCursorService
# con `from` y deja correr los mismos jobs incrementales del cron (RevenueIntelligence::SyncZoho*Job),
# que ya son idempotentes y manejan paginación/errores por-registro. Si el rango trae más registros
# de los que un job procesa en una corrida (tope MAX_PAGES de cada job), volver a correr esta tarea
# avanza desde donde quedó el cursor — no hace falta una segunda ruta de código para "backfill vs.
# incremental".
class RevenueIntelligence::BackfillService
  JOB_BY_SYNC_TYPE = {
    'leads' => RevenueIntelligence::SyncZohoLeadsJob,
    'deals' => RevenueIntelligence::SyncZohoDealsJob,
    'stage_history' => RevenueIntelligence::SyncZohoStageHistoryJob,
    'meetings' => RevenueIntelligence::SyncZohoMeetingsJob
  }.freeze

  def initialize(account:, from:)
    @account = account
    @from = from
  end

  # Conteo aproximado de Leads/Deals modificados desde `from` — solo primera página, para el
  # mensaje de DRY RUN. "N+" indica que hay más páginas (el conteo real solo se sabe importando).
  def preview_counts
    { leads: preview_count(Crm::Zoho::Api::LeadsClient.new(hook)), deals: preview_count(Crm::Zoho::Api::DealsClient.new(hook)) }
  end

  def perform!
    seed_cursors!
    JOB_BY_SYNC_TYPE.each_value { |job_class| job_class.perform_now(account.id) }
    RevenueIntelligence::ResolveIdentityJob.perform_now(account.id)
  end

  private

  attr_reader :account, :from

  def hook
    @hook ||= Integrations::Hook.find_by(account: account, app_id: 'zoho_crm', status: 'enabled')
  end

  def preview_count(client)
    criteria = "(Modified_Time:between:#{from.iso8601},#{Time.current.iso8601})"
    result = client.search_by_criteria(criteria, page: 1, per_page: 200)
    result[:more_records] ? "#{result[:data].size}+ (hay más páginas)" : result[:data].size.to_s
  end

  # cursor.last_synced_at = min(valor actual, from): garantiza que el siguiente sync cubra AL
  # MENOS desde `from` — si el cursor ya estaba más adelante (más reciente) que `from`, se
  # retrocede para forzar re-cubrir ese rango (seguro/idempotente gracias a los índices únicos de
  # cada tabla revenue_*). Si el cursor ya estaba más atrás que `from` (o no existía todavía), no
  # hay nada que ajustar: el siguiente sync incremental normal ya cubre `from` y más.
  def seed_cursors!
    JOB_BY_SYNC_TYPE.each_key do |sync_type|
      cursor = account.revenue_sync_cursors.find_or_initialize_by(sync_type: sync_type)
      cursor.last_synced_at = from if cursor.last_synced_at.blank? || cursor.last_synced_at > from
      cursor.save!
    end
  end
end
