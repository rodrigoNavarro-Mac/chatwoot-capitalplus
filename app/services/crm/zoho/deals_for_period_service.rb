# Trae todos los Deals de Zoho de UN desarrollo, creados dentro de un rango de fechas — usado por
# V2::Reports::ZohoLeadsMetrics para el KPI de "deals creados"/"% conversión" del reporte semanal
# operativo. Calco de Crm::Zoho::LeadsForPeriodService pero contra el módulo Deals.
#
# OJO: el campo personalizado de desarrollo se llama "Desarrollo" (dos erres) en el módulo Leads,
# pero "Desarollo" (una sola erre — error tipográfico ya existente en la configuración de esta
# cuenta de Zoho) en el módulo Deals. Confirmado contra la API real (no es un typo de este código).
class Crm::Zoho::DealsForPeriodService
  MAX_DEALS = 2000 # tope de seguridad — evita paginar indefinidamente si el filtro sale mal
  PER_PAGE = 200 # máximo permitido por Zoho en /search

  def initialize(account:, development_key:, range:)
    @account = account
    @development_key = development_key
    @range = range
  end

  def fetch
    return [] if development_key.blank? || range.blank? || hook.blank?

    fetch_all_pages
  rescue Crm::Zoho::Api::BaseClient::ApiError, Net::OpenTimeout, Net::ReadTimeout => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
    []
  end

  private

  attr_reader :account, :development_key, :range

  def fetch_all_pages
    deals = []
    page = 1

    loop do
      result = deals_client.search_by_criteria(criteria, page: page, per_page: PER_PAGE)
      deals.concat(result[:data])
      break unless result[:more_records] && deals.size < MAX_DEALS

      page += 1
    end

    deals
  end

  def deals_client
    @deals_client ||= Crm::Zoho::Api::DealsClient.new(hook)
  end

  def hook
    @hook ||= Integrations::Hook.find_by(account: account, app_id: 'zoho_crm', status: 'enabled')
  end

  def criteria
    "(Desarollo:equals:#{development_key})and(Created_Time:between:#{since_iso},#{until_iso})"
  end

  def since_iso
    zoho_iso(range.begin)
  end

  def until_iso
    zoho_iso(range.end)
  end

  def zoho_iso(datetime)
    timezone = account.reporting_timezone.presence || 'UTC'
    datetime.to_time.in_time_zone(timezone).iso8601
  end
end
