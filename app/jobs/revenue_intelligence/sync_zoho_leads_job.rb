# Sincroniza Zoho Leads -> revenue_leads. Solo lectura sobre Zoho, nunca crea/modifica nada allá.
# Incremental por Modified_Time con un cursor propio (RevenueIntelligence::SyncCursorService,
# sync_type "leads") — sin filtro de Desarrollo a propósito (a diferencia de
# Crm::Zoho::LeadsForPeriodService): este job sincroniza TODOS los desarrollos, el data mart debe
# soportar multi-desarrollo desde el día uno.
#
# La primera corrida (sin cursor todavía) solo trae una ventana corta reciente — el histórico
# completo se importa aparte vía `lib/tasks/backfill_revenue_intelligence.rake`, no aquí.
class RevenueIntelligence::SyncZohoLeadsJob < ApplicationJob
  queue_as :scheduled_jobs

  PER_PAGE = 200
  # Tope de seguridad — evita paginar indefinidamente si el filtro sale mal (mismo criterio que
  # Crm::Zoho::LeadsForPeriodService::MAX_LEADS, aquí en páginas en vez de registros).
  MAX_PAGES = 50
  # Ventana de solapamiento aplicada en cada corrida sobre el cursor guardado, para tolerar que
  # Modified_Time no siempre bumpee exactamente al mismo segundo que un cambio real.
  OVERLAP = 10.minutes
  # Ventana de la primera corrida (cursor todavía sin valor) — nunca hace backfill completo desde
  # el cron, eso es responsabilidad exclusiva del rake task.
  INITIAL_WINDOW = 24.hours

  def perform(account_id = nil)
    hooks = Integrations::Hook.enabled.where(app_id: 'zoho_crm')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      sync_hook(hook)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::SyncZohoLeadsJob] hook=#{hook.id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: hook.account).capture_exception
    end
  end

  private

  def sync_hook(hook)
    account = hook.account
    cursor_service = RevenueIntelligence::SyncCursorService.new(account, 'leads')
    since = (cursor_service.since || INITIAL_WINDOW.ago) - OVERLAP
    until_at = Time.current

    client = Crm::Zoho::Api::LeadsClient.new(hook)
    fetch_all_pages(client, account, since, until_at).each { |payload| upsert_lead(account, payload) }

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

  def upsert_lead(account, payload)
    zoho_lead_id = payload['id']
    return if zoho_lead_id.blank?

    lead = account.revenue_leads.find_or_initialize_by(zoho_lead_id: zoho_lead_id)
    lead.assign_attributes(RevenueIntelligence::LeadMapper.map(payload).merge(synced_at: Time.current))
    lead.save!
  end
end
