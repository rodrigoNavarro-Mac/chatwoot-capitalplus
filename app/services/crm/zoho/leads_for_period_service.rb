# Trae todos los Leads de Zoho de UN desarrollo, TOCADOS (creados o modificados) dentro de un rango
# de fechas — usado por V2::Reports::WeeklyOpsReportBuilder para las secciones de distribución del
# pipeline, fuentes de prospectos, conversión por dueño y motivos de descarte del reporte semanal
# operativo.
#
# Se filtra por Modified_Time OR Created_Time, no solo por Modified_Time: un lead creado hace
# semanas que recién se contactó o se marcó como perdido ESTA semana sigue siendo el caso que
# Modified_Time por sí solo ya cubría (detectado 2026-08-18: la gráfica de conversión por dueño
# salía vacía por este motivo). Pero un lead CREADO dentro del rango al que un asesor le dio
# seguimiento DESPUÉS de que el rango cerró (el caso normal: septiembre crea el lead, octubre lo
# sigue trabajando) tiene Modified_Time fuera de rango y Created_Time dentro — con solo
# Modified_Time ese lead desaparecía de TODA la consulta (no solo de "nuevos"), aunque sí llegó en
# el periodo. Caso real confirmado 2026-10-07 cruzando contra la API de Zoho en vivo: de 149 leads
# realmente creados en un mes para un desarrollo, el reporte solo traía 94 (faltaban 55, un 37%) —
# el mismo hueco inflaba "Motivos de descarte" de leads nuevos y diluía "% conversión" de deals
# creados, porque ambos dependen de este mismo fetch. Usar el OR es la única forma de no perder
# ninguna de las dos poblaciones (nuevos / seguimiento) en una sola llamada a /search.
#
# No hay copia local de Leads de Zoho (a diferencia de zoho_deal_stage, que sí se cachea vía
# Crm::Zoho::DealsSyncJob) ni scope de COQL en esta integración, así que se consulta la API en vivo
# con Leads/search y se pagina. Un fallo de Zoho (timeout, error de API, credenciales inválidas)
# nunca debe tumbar el resto del reporte — se reporta a Sentry y se devuelve un array vacío.
class Crm::Zoho::LeadsForPeriodService
  MAX_LEADS = 2000 # tope de seguridad — evita paginar indefinidamente si el filtro sale mal
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
    leads = []
    page = 1

    loop do
      result = leads_client.search_by_criteria(criteria, page: page, per_page: PER_PAGE)
      leads.concat(result[:data])
      break unless result[:more_records] && leads.size < MAX_LEADS

      page += 1
    end

    leads
  end

  def leads_client
    @leads_client ||= Crm::Zoho::Api::LeadsClient.new(hook)
  end

  def hook
    @hook ||= Integrations::Hook.find_by(account: account, app_id: 'zoho_crm', status: 'enabled')
  end

  def criteria
    "(Desarrollo:equals:#{development_key})and" \
      "((Created_Time:between:#{since_iso},#{until_iso})or(Modified_Time:between:#{since_iso},#{until_iso}))"
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
