# Sincroniza Zoho Deals -> revenue_deals. Solo lectura sobre Zoho. Mismo patrón incremental que
# RevenueIntelligence::SyncZohoLeadsJob — ver ese archivo para el razonamiento de la ventana con
# solapamiento y por qué no hace backfill completo desde el cron.
class RevenueIntelligence::SyncZohoDealsJob < ApplicationJob
  queue_as :scheduled_jobs

  PER_PAGE = 200
  MAX_PAGES = 50
  OVERLAP = 10.minutes
  INITIAL_WINDOW = 24.hours

  # until_at: solo lo usa RevenueIntelligence::BackfillService para acotar la ventana en tramos
  # (la búsqueda de Zoho rechaza cualquier criteria que devuelva más de 2000 registros); el cron
  # nunca lo pasa, siempre sincroniza hasta el momento actual.
  def perform(account_id = nil, until_at: nil)
    hooks = Integrations::Hook.enabled.where(app_id: 'zoho_crm')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      sync_hook(hook, until_at: until_at)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::SyncZohoDealsJob] hook=#{hook.id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: hook.account).capture_exception
    end
  end

  private

  def sync_hook(hook, until_at: nil)
    account = hook.account
    cursor_service = RevenueIntelligence::SyncCursorService.new(account, 'deals')
    since = (cursor_service.since || INITIAL_WINDOW.ago) - OVERLAP
    until_at ||= Time.current

    client = Crm::Zoho::Api::DealsClient.new(hook)
    fully_synced = fetch_and_upsert_pages(client, account, since, until_at)

    cursor_service.advance!(until_at) if fully_synced
  rescue StandardError => e
    cursor_service&.record_error!(e.message)
    raise
  end

  # Guarda cada página en cuanto llega — ver el mismo razonamiento en SyncZohoLeadsJob. Devuelve
  # false si el loop se cortó por MAX_PAGES habiendo todavía more_records — el caller no debe
  # avanzar el cursor en ese caso (ver SyncZohoLeadsJob#fetch_and_upsert_pages).
  def fetch_and_upsert_pages(client, account, since, until_at)
    criteria = "(Modified_Time:between:#{zoho_iso(since)},#{zoho_iso(until_at)})"
    page = 1

    loop do
      result = client.search_by_criteria(criteria, page: page, per_page: PER_PAGE)
      result[:data].each { |payload| upsert_deal(account, payload) }

      if result[:more_records] && page >= MAX_PAGES
        Rails.logger.warn("[RevenueIntelligence::SyncZohoDealsJob] account=#{account.id} truncado en " \
                          "MAX_PAGES=#{MAX_PAGES} (Zoho todavía reporta more_records) since=#{since.iso8601} " \
                          "until=#{until_at.iso8601} -- el cursor no avanza esta corrida.")
        return false
      end
      break unless result[:more_records]

      page += 1
    end
    true
  end

  def zoho_iso(time)
    time.in_time_zone(RevenueIntelligence::TIMEZONE).iso8601
  end

  def upsert_deal(account, payload)
    zoho_deal_id = payload['id']
    return if zoho_deal_id.blank?

    deal = account.revenue_deals.find_or_initialize_by(zoho_deal_id: zoho_deal_id)
    save_deal!(deal, payload)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Carrera entre dos corridas concurrentes del mismo sync sobre el mismo zoho_deal_id: otro
    # proceso ya insertó la fila entre el find_or_initialize_by y el save!. Según qué tan cerca
    # coincidan en el tiempo, esto llega como RecordNotUnique (choque real en el índice de BD) o
    # como RecordInvalid "has already been taken" (la validación de Rails ya alcanza a verla). En
    # ambos casos: releer directo del modelo (no de la asociación cacheada, ver
    # feedback_ar_association_cache_and_time_precision) y reintentar el mismo upsert una sola vez
    # sobre la fila ganadora.
    deal = RevenueDeal.find_by!(account_id: account.id, zoho_deal_id: zoho_deal_id)
    save_deal!(deal, payload)
  end

  def save_deal!(deal, payload)
    deal.assign_attributes(RevenueIntelligence::DealMapper.map(payload).merge(synced_at: Time.current))
    deal.save!
  end
end
