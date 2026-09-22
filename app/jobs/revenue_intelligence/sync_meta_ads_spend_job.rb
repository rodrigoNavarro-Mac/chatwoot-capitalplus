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

  def perform(account_id = nil)
    hooks = Integrations::Hook.enabled.where(app_id: 'meta_ads')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      sync_hook(hook)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::SyncMetaAdsSpendJob] hook=#{hook.id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: hook.account).capture_exception
    end
  end

  private

  def sync_hook(hook)
    ad_account_id = hook.settings['ad_account_id']
    return if ad_account_id.blank?

    client = Koala::Facebook::API.new(hook.access_token)
    return unless currency_supported?(client, ad_account_id, hook.account)

    since = RECHECK_WINDOW.ago.to_date
    until_date = Time.current.in_time_zone(RevenueIntelligence::TIMEZONE).to_date

    each_insight_row(client, ad_account_id, since, until_date) { |row| upsert_spend(hook.account, row) }
  end

  # Meta no expone la moneda en cada fila de insights -- se lee una sola vez de la cuenta
  # publicitaria. Aborta en vez de guardar un monto en la moneda equivocada silenciosamente
  # (RevenueAdSpend::CURRENCIES solo acepta MXN hoy).
  def currency_supported?(client, ad_account_id, account)
    currency = client.get_object(ad_account_id, fields: 'currency')['currency']
    return true if currency == EXPECTED_CURRENCY

    Rails.logger.error("[RevenueIntelligence::SyncMetaAdsSpendJob] account=#{account.id} " \
                       "ad_account=#{ad_account_id} moneda inesperada=#{currency.inspect}, se esperaba #{EXPECTED_CURRENCY} -- sync omitido")
    false
  end

  def each_insight_row(client, ad_account_id, since, until_date, &)
    time_range = { since: since.iso8601, until: until_date.iso8601 }.to_json
    page = client.api("#{ad_account_id}/insights", {
      level: 'ad', time_increment: 1, time_range: time_range,
      fields: 'campaign_name,adset_name,ad_name,spend,date_start'
    }.compact)

    loop do
      page.each(&)
      break if page.next_page.blank?

      page = page.next_page
    end
  end

  def upsert_spend(account, row)
    return if row['spend'].blank?

    date = Date.parse(row['date_start'])
    spend = account.revenue_ad_spends.find_or_initialize_by(
      campaign_name: row['campaign_name'], adset_name: row['adset_name'], advert_name: row['ad_name'],
      period_start: date, period_end: date
    )
    spend.assign_attributes(amount: row['spend'].to_f, currency: EXPECTED_CURRENCY, source: 'meta_api')
    spend.save!
  end
end
