# No hereda de OauthCallbackController (a diferencia de Notion/Google/Microsoft) -- ese helper
# intercambia el code por tokens vía el gem oauth2, que por default manda los parámetros como body
# form-encoded. Crm::Zoho::TokenRefreshService (ya en producción, funcionando) confirma que Zoho
# para ESTA cuenta acepta el intercambio como query params de un POST -- se replica ese mismo shape
# aquí en vez de arriesgar un flujo sin probar contra el endpoint real la primera vez que un usuario
# complete el consentimiento.
class ZohoCrm::CallbacksController < ApplicationController
  include AccountFromSignedIdConcern

  def show
    return redirect_with_error('missing_code') if params[:code].blank?

    pending = fetch_pending_oauth
    return redirect_with_error('expired_or_missing_state') unless pending

    token_response = exchange_code_for_tokens(pending)
    return redirect_with_error(token_response['error']) if token_response['error'].present?
    return redirect_with_error('no_refresh_token') if token_response['refresh_token'].blank?

    persist_hook!(pending, token_response)
    ::Redis::Alfred.delete(pending_oauth_key)

    redirect_to zoho_crm_settings_url(connected: true), allow_other_host: true
  rescue StandardError => e
    handle_unexpected_error(e)
  end

  private

  # `account` puede fallar a su vez si el `state` es inválido/expiró (caso esperado, no solo
  # errores de programación) -- se resuelve una sola vez de forma segura para no volver a lanzar
  # dentro del propio rescue, y cae a la home si no se pudo resolver ninguna cuenta.
  def handle_unexpected_error(exception)
    ChatwootExceptionTracker.new(exception, account: safe_account).capture_exception
    return redirect_to '/' unless safe_account

    redirect_to zoho_crm_settings_url(error: 'unexpected_error'), allow_other_host: true
  end

  def pending_oauth_key
    format(::Redis::Alfred::ZOHO_CRM_PENDING_OAUTH, state: params[:state])
  end

  def fetch_pending_oauth
    raw = ::Redis::Alfred.get(pending_oauth_key)
    return nil if raw.blank?

    JSON.parse(raw)
  end

  def exchange_code_for_tokens(pending)
    response = HTTParty.post(
      "https://accounts.zoho.#{pending['datacenter']}/oauth/v2/token",
      query: {
        client_id: pending['client_id'],
        client_secret: pending['client_secret'],
        code: params[:code],
        redirect_uri: "#{base_url}/zoho_crm/callback",
        grant_type: 'authorization_code'
      },
      headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
    )

    response.parsed_response
  end

  # settings_json_schema tiene additionalProperties: false -- ZohoCrmController#fetch_or_cache_org_key
  # cachea una clave 'zoho_org_key' fuera de ese esquema vía update_columns (que sí bypassa la
  # validación) precisamente porque save! la rechazaría. Se preservan solo las claves declaradas en
  # el esquema (más las 4 nuevas) para que un hook reconectado que ya tenía 'zoho_org_key' cacheado
  # no rompa la validación aquí.
  SCHEMA_PRESERVED_KEYS = %w[webhook_secret enable_conversation_note enable_transcript_note].freeze

  def persist_hook!(pending, token_response)
    hook = account.hooks.find_or_initialize_by(app_id: 'zoho_crm')
    was_reconnect = hook.persisted?

    hook.status = 'enabled'
    hook.settings = hook.settings.slice(*SCHEMA_PRESERVED_KEYS).merge(
      'client_id' => pending['client_id'],
      'client_secret' => pending['client_secret'],
      'refresh_token' => token_response['refresh_token'],
      'datacenter' => pending['datacenter']
    )
    hook.save!

    # El access_token cacheado (si lo había) corresponde al refresh_token viejo -- sin esto, la
    # próxima llamada seguiría usando un access_token cacheado de un token ya inválido hasta que
    # expire su TTL propio (hasta 55 min, ver TokenRefreshService::TOKEN_TTL_SECONDS).
    Crm::Zoho::TokenRefreshService.new(hook).invalidate! if was_reconnect
  end

  def zoho_crm_settings_url(**query)
    "#{base_url}/app/accounts/#{account.id}/settings/integrations/zoho_crm?#{query.to_query}"
  end

  # `state` puede venir vacío/inválido/expirado en cualquiera de estos casos tempranos -- resolver
  # la cuenta puede fallar aquí también (no solo en el rescue general), así que cae a la home en vez
  # de propagar la excepción de account_from_signed_id.
  def redirect_with_error(error_code)
    return redirect_to '/' unless safe_account

    redirect_to zoho_crm_settings_url(error: error_code.presence || 'unknown_error'), allow_other_host: true
  end

  # account_from_signed_id lanza si `state` está vacío/inválido/expirado -- un caso esperado aquí
  # (no solo un bug), así que se resuelve de forma segura en vez de dejar que se propague.
  def safe_account
    account
  rescue StandardError
    nil
  end

  def base_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end
end
