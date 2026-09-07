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
    fetch_and_upsert_pages(client, account, since, until_at)

    cursor_service.advance!(until_at)
  rescue StandardError => e
    cursor_service&.record_error!(e.message)
    raise
  end

  # Guarda cada página en cuanto llega, en vez de acumular todas y guardar al final — si una
  # página posterior falla (ej. límite de 2000 registros de la búsqueda de Zoho), las páginas
  # anteriores ya sincronizadas no se pierden.
  def fetch_and_upsert_pages(client, account, since, until_at)
    criteria = "(Modified_Time:between:#{zoho_iso(account, since)},#{zoho_iso(account, until_at)})"
    page = 1

    loop do
      # converted: 'both' — sin esto, la búsqueda de Zoho EXCLUYE por default los leads ya
      # convertidos a Deal (confirmado contra la API real), y revenue_deals.revenue_lead_id nunca
      # se puede resolver porque su lead de origen jamás llega a sincronizarse.
      result = client.search_by_criteria(criteria, page: page, per_page: PER_PAGE, converted: 'both')
      result[:data].each { |payload| upsert_lead(account, payload) }
      break unless result[:more_records] && page < MAX_PAGES

      page += 1
    end
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
    link_converted_deal(account, lead, payload)
  end

  # Zoho no expone el id del Lead de origen en el payload del Deal — sí al revés: un Lead
  # convertido trae Converted_Deal: {id:, name:} apuntando al Deal resultante (confirmado contra
  # la API real). Best-effort: si ese Deal todavía no está sincronizado, queda sin enlazar hasta
  # que una corrida futura (de este mismo job, tras un nuevo sync de Deals) lo encuentre.
  def link_converted_deal(account, lead, payload)
    converted_deal_id = payload.dig('Converted_Deal', 'id')
    return if converted_deal_id.blank?

    deal = account.revenue_deals.find_by(zoho_deal_id: converted_deal_id)
    return if deal.blank? || deal.revenue_lead_id.present?

    deal.update!(revenue_lead_id: lead.id)
  end
end
