# Sincroniza gasto por anuncio desde Meta Marketing API (Graph API Insights) -> revenue_ad_spends
# (source: meta_api). Ver Fase 1/2 del plan de integración con Meta Ads (sesión 2026-09-22):
# Zoho nunca entrega un id real de campaña/adset/anuncio para esta cuenta, así que el cruce con
# revenue_leads/revenue_deals sigue siendo por NOMBRE (ver RevenueIntelligence::LeadMapper) -- este
# job solo trae el gasto, no intenta resolver ids.
#
# Solo lectura sobre Meta, nunca crea/modifica campañas (el Hook solo tiene permiso ads_read).
class RevenueIntelligence::SyncMetaAdsSpendJob < ApplicationJob
  queue_as :scheduled_jobs

  # Ventana de recorrido en cada corrida: Meta ajusta el spend reportado unos días después del
  # evento (conversiones atribuidas tardías, correcciones de facturación) -- mismo RECHECK_WINDOW
  # que ya usa RevenueIntelligence::RefreshAggregatesJob para autocorregirse.
  RECHECK_WINDOW = 7.days
  EXPECTED_CURRENCY = 'MXN'.freeze
  # Koala nunca fija una versión de Graph API por defecto (ni Koala.config.api_version ni un
  # default propio del gem) -- sin especificarla, Meta la resuelve a una versión histórica ya
  # deprecada y rechaza la llamada (visto en producción: OAuthException code 2635 "calling a
  # deprecated version of the Ads API"). Se pasa explícito por llamada (no vía Koala.config
  # global) para no afectar el canal de Messenger, que también usa Koala en este mismo código base
  # sin haber tenido este problema hasta ahora.
  GRAPH_API_VERSION = 'v25.0'.freeze

  # since/until_date: nil en la corrida horaria normal (usa la ventana móvil de RECHECK_WINDOW).
  # Se exponen para permitir un backfill histórico manual desde consola -- Meta guarda insights
  # hasta ~37 meses atrás -- reutilizando este mismo job/lógica en vez de duplicar código, mismo
  # criterio que RevenueIntelligence::SyncZohoLeadsJob con su parámetro until_at.
  def perform(account_id = nil, since: nil, until_date: nil)
    hooks = Integrations::Hook.enabled.where(app_id: 'meta_ads')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      sync_hook(hook, since: since, until_date: until_date)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::SyncMetaAdsSpendJob] hook=#{hook.id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: hook.account).capture_exception
    end
  end

  private

  # La Graph API exige el prefijo "act_" para referenciar una cuenta publicitaria (ver error real
  # de producción: sin el prefijo, Meta responde error_subcode 33 "Object ... does not exist" en
  # vez de un 404 claro). El Business Manager muestra el ID solo con dígitos en varias pantallas,
  # así que es fácil pegarlo sin el prefijo al configurar el Hook -- normalizarlo acá evita
  # depender de que quede bien tecleado a mano.
  def normalize_ad_account_id(ad_account_id)
    return nil if ad_account_id.blank?

    ad_account_id.start_with?('act_') ? ad_account_id : "act_#{ad_account_id}"
  end

  def sync_hook(hook, since: nil, until_date: nil)
    ad_account_id = normalize_ad_account_id(hook.settings['ad_account_id'])
    return if ad_account_id.blank?

    client = Koala::Facebook::API.new(hook.access_token)
    return unless currency_supported?(client, ad_account_id, hook.account)

    since ||= RECHECK_WINDOW.ago.to_date
    until_date ||= Time.current.in_time_zone(RevenueIntelligence::TIMEZONE).to_date
    hook_desarrollo = hook.settings['desarrollo'].presence

    each_insight_row(client, ad_account_id, since, until_date) { |row| upsert_spend(hook.account, row, hook_desarrollo) }
  end

  # Meta no expone la moneda en cada fila de insights -- se lee una sola vez de la cuenta
  # publicitaria. Aborta en vez de guardar un monto en la moneda equivocada silenciosamente
  # (RevenueAdSpend::CURRENCIES solo acepta MXN hoy).
  def currency_supported?(client, ad_account_id, account)
    currency = client.get_object(ad_account_id, { fields: 'currency' }, { api_version: GRAPH_API_VERSION })['currency']
    return true if currency == EXPECTED_CURRENCY

    Rails.logger.error("[RevenueIntelligence::SyncMetaAdsSpendJob] account=#{account.id} " \
                       "ad_account=#{ad_account_id} moneda inesperada=#{currency.inspect}, se esperaba #{EXPECTED_CURRENCY} -- sync omitido")
    false
  end

  # graph_call, no api: #api es la capa HTTP cruda (devuelve un Koala::HTTPService::Response sin
  # parsear, ni error-checking ni GraphCollection -- visto en producción: NoMethodError "undefined
  # method 'each'"). #graph_call es lo que parsea el JSON, revisa errores, y envuelve resultados
  # paginables en GraphCollection -- es lo que get_object/get_page usan internamente.
  # Fase 22: se agregan campaign_id/adset_id/ad_id/account_id al mismo fields: ya autorizado por
  # ads_read -- NO requiere ningún permiso nuevo (son columnas de la misma fila de insights, ver
  # docs/investigacion-tesis-ia/26_DISENO_ATRIBUCION_DETERMINISTICA_FASE21.md §2). Se guardan
  # como metadato aditivo (RevenueAdSpend#meta_*), nunca como llave de deduplicación -- ver
  # upsert_spend y el comentario de la migración AddMetaIdsToRevenueAdSpends.
  def each_insight_row(client, ad_account_id, since, until_date, &)
    time_range = { since: since.iso8601, until: until_date.iso8601 }.to_json
    page = client.graph_call("#{ad_account_id}/insights", {
      level: 'ad', time_increment: 1, time_range: time_range,
      fields: 'campaign_name,adset_name,ad_name,spend,date_start,account_id,campaign_id,adset_id,ad_id'
    }.compact, 'get', { api_version: GRAPH_API_VERSION })

    loop do
      page.each(&)
      break if page.next_page.blank?

      page = page.next_page
    end
  end

  # Se resuelve el desarrollo POR CAMPAÑA (RevenueIntelligence::MetaAdsDesarrolloResolver), nunca
  # un valor fijo por Hook/cuenta -- una sola cuenta publicitaria puede correr campañas de varios
  # desarrollos a la vez (confirmado en producción: la cuenta "Fuego Cancún" también trae Amura y
  # P. Quintana Roo). hook_desarrollo solo se usa como respaldo si el nombre de campaña no matchea
  # ningún alias conocido -- útil para una cuenta que de verdad sea de un solo desarrollo, pero
  # nunca debe usarse en una cuenta ya confirmada como multi-desarrollo (ahí mejor dejarlo sin
  # configurar en el Hook, para que lo no resuelto quede en nil/N-D visible, no mal etiquetado).
  # IMPORTANTE (Fase 22 §1): la llave de find_or_initialize_by sigue siendo por NOMBRE, sin
  # cambios -- NUNCA se busca por meta_campaign_id/meta_adset_id/meta_ad_id. Hacerlo
  # reescribiría campaign_name/adset_name/advert_name en filas históricas en cada
  # resincronización (Meta siempre reporta el nombre VIGENTE, incluso para fechas pasadas) y
  # rompería el match por nombre que usa V2::Reports::RevenueIntelligenceBuilder contra los
  # dimension_id de los rollups (generados con el nombre con el que se creó cada Lead/Deal en su
  # momento). Los campos meta_* se guardan como metadato adicional; una campaña renombrada sigue
  # fragmentándose en dos filas por nombre, igual que hoy, pero ambas comparten el mismo
  # meta_campaign_id -- consultas futuras pueden des-fragmentar agrupando por ID sin migrar ni
  # mutar ninguna fila existente.
  def upsert_spend(account, row, hook_desarrollo)
    return if row['spend'].blank?

    date = Date.parse(row['date_start'])
    desarrollo = RevenueIntelligence::MetaAdsDesarrolloResolver.resolve(row['campaign_name']) || hook_desarrollo
    spend = account.revenue_ad_spends.find_or_initialize_by(
      campaign_name: row['campaign_name'], adset_name: row['adset_name'], advert_name: row['ad_name'],
      period_start: date, period_end: date
    )

    new_amount = row['spend'].to_f
    observed_at = Time.current
    # Solo tiene sentido "revisar" un valor que ya existía -- una fila recién creada no tiene
    # importe previo con el cual compararse (Fase 22 §3: revisiones solo ante cambio EFECTIVO).
    spend.record_revision_if_changed!(new_amount, observed_at: observed_at) unless spend.new_record?

    spend.assign_attributes(
      amount: new_amount, currency: EXPECTED_CURRENCY, source: 'meta_api', desarrollo: desarrollo,
      meta_ad_account_id: row['account_id'], meta_campaign_id: row['campaign_id'],
      meta_adset_id: row['adset_id'], meta_ad_id: row['ad_id'], last_synced_at: observed_at
    )
    spend.save!
  end
end
