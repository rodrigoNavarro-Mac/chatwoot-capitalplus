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

  # leads/deals usan Modified_Time:between en Crm::Zoho::Api::*Client#search_by_criteria, que
  # Zoho rechaza con "LIMIT_REACHED" si el rango pedido devuelve más de 2000 registros — algo que
  # un rango histórico de meses/años supera fácilmente en cuentas con mucho "ruido" de
  # Modified_Time (reasignaciones, notas, automatizaciones, no solo altas/cambios reales).
  # stage_history/meetings iteran por-registro (un request por deal/lead ya sincronizado), sin
  # ese límite, así que no necesitan chunking.
  CHUNKABLE_SYNC_TYPES = %w[leads deals].freeze
  DEFAULT_CHUNK = 1.day
  MIN_CHUNK = 15.minutes
  LIMIT_REACHED_MARKER = 'LIMIT_REACHED'.freeze

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
    CHUNKABLE_SYNC_TYPES.each { |sync_type| chunked_sync(sync_type) }
    (JOB_BY_SYNC_TYPE.keys - CHUNKABLE_SYNC_TYPES).each { |sync_type| JOB_BY_SYNC_TYPE.fetch(sync_type).perform_now(account.id) }
    RevenueIntelligence::ResolveIdentityJob.perform_now(account.id)
  end

  private

  attr_reader :account, :from

  # Avanza en tramos de tamaño ADAPTATIVO en vez de pedir todo el rango de una vez: si un tramo
  # falla por el límite de 2000 de Zoho, se parte a la mitad y se reintenta desde el MISMO punto
  # (el cursor no avanzó, seguro reintentar); si tiene éxito, el siguiente tramo vuelve a crecer
  # hacia DEFAULT_CHUNK. Así no hace falta que quien corre el backfill adivine un rango que quepa.
  def chunked_sync(sync_type)
    job_class = JOB_BY_SYNC_TYPE.fetch(sync_type)
    chunk = DEFAULT_CHUNK
    # Fijo, tomado UNA vez (Time.current es un blanco móvil — compararlo recalculado en cada
    # vuelta nunca converge) y TRUNCADO a segundos enteros: el cursor viaja a/desde Postgres en
    # cada tramo, y el redondeo de punto flotante del viaje redondo puede perder una fracción de
    # microsegundo — comparar un valor sin fracción contra el releído de la BD sí converge exacto
    # (bug real encontrado en desarrollo: el loop giraba miles de veces sin terminar nunca,
    # `since` quedándose una fracción de segundo por debajo de `deadline` para siempre).
    deadline = Time.current.change(usec: 0)

    until cursor_since(sync_type) >= deadline
      target = [cursor_since(sync_type) + chunk, deadline].min
      job_class.perform_now(account.id, until_at: target)
      cursor = fresh_cursor(sync_type)

      chunk = cursor.last_run_status == 'failed' ? shrink_chunk_or_raise(sync_type, cursor, chunk) : [chunk * 2, DEFAULT_CHUNK].min
    end
  end

  def shrink_chunk_or_raise(sync_type, cursor, chunk)
    unless cursor.last_error.to_s.include?(LIMIT_REACHED_MARKER)
      raise "No se pudo sincronizar #{sync_type} (cuenta #{account.id}): #{cursor.last_error}"
    end

    if chunk <= MIN_CHUNK
      raise "No se pudo sincronizar #{sync_type} (cuenta #{account.id}) incluso con el tramo mínimo " \
            "(#{MIN_CHUNK.inspect}): #{cursor.last_error}"
    end

    chunk / 2
  end

  # Consulta directa a RevenueSyncCursor (no vía account.revenue_sync_cursors) — la asociación
  # puede quedar "loaded" (cacheada en memoria) por una llamada anterior en la misma cuenta, y
  # entonces #find_by filtra el array ya cargado en vez de ir a la base de datos: el chunked_sync
  # de arriba jamás vería el cursor avanzar (bug real encontrado en desarrollo — el loop giraba
  # miles de veces sin converger, con `since` congelado, aunque el job sí actualizaba la fila).
  def cursor_since(sync_type)
    fresh_cursor(sync_type).last_synced_at
  end

  def fresh_cursor(sync_type)
    RevenueSyncCursor.find_by(account_id: account.id, sync_type: sync_type)
  end

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
