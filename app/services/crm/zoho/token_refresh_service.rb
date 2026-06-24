class Crm::Zoho::TokenRefreshService
  TOKEN_TTL_SECONDS = 55 * 60

  def initialize(hook)
    @hook = hook
    @client_id = hook.settings['client_id']
    @client_secret = hook.settings['client_secret']
    @refresh_token = hook.settings['refresh_token']
    @datacenter = hook.settings['datacenter'].presence || 'com'
  end

  def token
    cached = ::Redis::Alfred.get(cache_key)
    return cached if cached.present?

    fetch_and_cache_token
  end

  def invalidate!
    ::Redis::Alfred.delete(cache_key)
  end

  private

  def fetch_and_cache_token
    response = HTTParty.post(
      "https://accounts.zoho.#{@datacenter}/oauth/v2/token",
      query: {
        client_id: @client_id,
        client_secret: @client_secret,
        refresh_token: @refresh_token,
        grant_type: 'refresh_token'
      },
      headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
    )

    raise "Zoho OAuth error: #{response.body}" unless response.success?

    access_token = response.parsed_response['access_token']
    raise 'Zoho OAuth returned no access_token' if access_token.blank?

    ::Redis::Alfred.setex(cache_key, access_token, TOKEN_TTL_SECONDS)
    access_token
  end

  def cache_key
    format(::Redis::Alfred::ZOHO_CRM_ACCESS_TOKEN, hook_id: @hook.id)
  end
end
