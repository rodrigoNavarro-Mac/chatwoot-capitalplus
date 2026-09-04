# Sincroniza Zoho Deals -> revenue_deals. Solo lectura sobre Zoho. Mismo patrón incremental que
# RevenueIntelligence::SyncZohoLeadsJob — ver ese archivo para el razonamiento de la ventana con
# solapamiento y por qué no hace backfill completo desde el cron.
class RevenueIntelligence::SyncZohoDealsJob < ApplicationJob
  queue_as :scheduled_jobs

  PER_PAGE = 200
  MAX_PAGES = 50
  OVERLAP = 10.minutes
  INITIAL_WINDOW = 24.hours

  def perform(account_id = nil)
    hooks = Integrations::Hook.enabled.where(app_id: 'zoho_crm')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      sync_hook(hook)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::SyncZohoDealsJob] hook=#{hook.id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: hook.account).capture_exception
    end
  end

  private

  def sync_hook(hook)
    account = hook.account
    cursor_service = RevenueIntelligence::SyncCursorService.new(account, 'deals')
    since = (cursor_service.since || INITIAL_WINDOW.ago) - OVERLAP
    until_at = Time.current

    client = Crm::Zoho::Api::DealsClient.new(hook)
    fetch_all_pages(client, account, since, until_at).each { |payload| upsert_deal(account, payload) }

    cursor_service.advance!(until_at)
  rescue StandardError => e
    cursor_service&.record_error!(e.message)
    raise
  end

  def fetch_all_pages(client, account, since, until_at)
    criteria = "(Modified_Time:between:#{zoho_iso(account, since)},#{zoho_iso(account, until_at)})"
    records = []
    page = 1

    loop do
      result = client.search_by_criteria(criteria, page: page, per_page: PER_PAGE)
      records.concat(result[:data])
      break unless result[:more_records] && page < MAX_PAGES

      page += 1
    end

    records
  end

  def zoho_iso(account, time)
    timezone = account.reporting_timezone.presence || 'UTC'
    time.in_time_zone(timezone).iso8601
  end

  def upsert_deal(account, payload)
    zoho_deal_id = payload['id']
    return if zoho_deal_id.blank?

    deal = account.revenue_deals.find_or_initialize_by(zoho_deal_id: zoho_deal_id)
    deal.assign_attributes(RevenueIntelligence::DealMapper.map(payload).merge(synced_at: Time.current))
    deal.save!
  end
end
