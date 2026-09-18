# A diferencia de Notion/Google (client_id/secret a nivel de instalación vía GlobalConfigService),
# Zoho CRM en este fork guarda client_id/client_secret/datacenter POR CUENTA en hook.settings (ver
# Api::V1::Accounts::Integrations::ZohoCrmController) — así que antes de poder construir la URL de
# autorización hace falta que el usuario los provea una vez (obtenidos de api-console.zoho.com, eso
# no se automatiza). Se guardan en Redis bajo el `state` firmado (15 min, mismo TTL que el propio
# state) para que Zoho::CallbacksController los recupere y complete el Hook en un solo paso junto
# con el refresh_token — evita dejar un Hook a medias si el usuario abandona el consentimiento.
class Api::V1::Accounts::ZohoCrm::AuthorizationsController < Api::V1::Accounts::OauthAuthorizationController
  # ZohoCRM.coql.READ: ausente en el token actual de producción (ver comentario en
  # Crm::Zoho::Api::DealsClient) -- se agrega aquí para cerrar ese gap ya documentado, sin costo (un
  # scope de más no rompe nada existente).
  SCOPE = 'ZohoCRM.modules.ALL,ZohoCRM.settings.ALL,ZohoCRM.org.ALL,ZohoCRM.coql.READ'.freeze
  PENDING_OAUTH_TTL = 15.minutes
  # Mismo enum que settings_json_schema (config/integration/apps.yml) para 'datacenter'.
  VALID_DATACENTERS = %w[com eu in com.au jp].freeze

  def create
    return render json: { success: false, error: 'missing_fields' }, status: :unprocessable_entity if missing_fields?

    unless VALID_DATACENTERS.include?(params[:datacenter])
      return render json: { success: false, error: 'invalid_datacenter' },
                    status: :unprocessable_entity
    end

    stashed_state = state
    ::Redis::Alfred.setex(pending_oauth_key(stashed_state), pending_payload.to_json, PENDING_OAUTH_TTL)

    render json: { success: true, url: authorize_url(stashed_state) }
  end

  private

  def missing_fields?
    %w[client_id client_secret datacenter].any? { |field| params[field].blank? }
  end

  def pending_payload
    {
      'client_id' => params[:client_id],
      'client_secret' => params[:client_secret],
      'datacenter' => params[:datacenter]
    }
  end

  def pending_oauth_key(stashed_state)
    format(::Redis::Alfred::ZOHO_CRM_PENDING_OAUTH, state: stashed_state)
  end

  def authorize_url(stashed_state)
    query = {
      scope: SCOPE,
      client_id: params[:client_id],
      response_type: 'code',
      access_type: 'offline',
      prompt: 'consent',
      redirect_uri: "#{base_url}/zoho_crm/callback",
      state: stashed_state
    }.to_query

    "https://accounts.zoho.#{params[:datacenter]}/oauth/v2/auth?#{query}"
  end
end
