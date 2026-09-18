require 'rails_helper'

RSpec.describe ZohoCrm::CallbacksController, type: :request do
  let(:account) { create(:account) }
  let(:state) { account.to_sgid.to_s }
  let(:oauth_code) { 'test_oauth_code' }
  let(:pending_payload) { { 'client_id' => 'zoho-client-id', 'client_secret' => 'zoho-client-secret', 'datacenter' => 'com' } }

  before { account.enable_features!('crm_integration') }

  def stash_pending!(oauth_state = state, payload = pending_payload)
    Redis::Alfred.setex(format(Redis::Alfred::ZOHO_CRM_PENDING_OAUTH, state: oauth_state), payload.to_json, 15.minutes)
  end

  describe 'GET /zoho_crm/callback' do
    context 'when code is missing' do
      it 'redirects to the settings page with an error' do
        stash_pending!

        get '/zoho_crm/callback', params: { state: state }

        expect(response).to redirect_to(%r{/settings/integrations/zoho_crm\?error=missing_code})
      end
    end

    context 'when the pending oauth payload is missing or expired' do
      it 'redirects to the settings page with an error' do
        get '/zoho_crm/callback', params: { code: oauth_code, state: state }

        expect(response).to redirect_to(%r{/settings/integrations/zoho_crm\?error=expired_or_missing_state})
      end
    end

    context 'when state is entirely invalid' do
      it 'redirects to the home page instead of raising' do
        get '/zoho_crm/callback', params: { code: oauth_code, state: 'garbage' }

        expect(response).to redirect_to('/')
      end
    end

    context 'when Zoho returns a token error' do
      before do
        stash_pending!
        stub_request(:post, %r{\Ahttps://accounts\.zoho\.com/oauth/v2/token})
          .to_return(status: 200, body: { error: 'invalid_code' }.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'redirects with the error and does not create a hook' do
        expect do
          get '/zoho_crm/callback', params: { code: oauth_code, state: state }
        end.not_to change(Integrations::Hook, :count)

        expect(response).to redirect_to(%r{/settings/integrations/zoho_crm\?error=invalid_code})
      end
    end

    context 'when Zoho succeeds and no hook exists yet' do
      before do
        stash_pending!
        stub_request(:post, %r{\Ahttps://accounts\.zoho\.com/oauth/v2/token})
          .to_return(status: 200, body: { access_token: 'at', refresh_token: 'rt' }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'creates an enabled zoho_crm hook with the 4 required settings and redirects with connected=true' do
        expect do
          get '/zoho_crm/callback', params: { code: oauth_code, state: state }
        end.to change(Integrations::Hook, :count).by(1)

        hook = account.hooks.find_by(app_id: 'zoho_crm')
        expect(hook.status).to eq('enabled')
        expect(hook.settings).to eq('client_id' => 'zoho-client-id', 'client_secret' => 'zoho-client-secret',
                                    'refresh_token' => 'rt', 'datacenter' => 'com')
        expect(response).to redirect_to(%r{/settings/integrations/zoho_crm\?connected=true})
      end

      it 'clears the pending oauth key from Redis' do
        get '/zoho_crm/callback', params: { code: oauth_code, state: state }

        expect(Redis::Alfred.get(format(Redis::Alfred::ZOHO_CRM_PENDING_OAUTH, state: state))).to be_nil
      end
    end

    context 'when reconnecting an existing hook' do
      let!(:hook) do
        h = account.hooks.create!(app_id: 'zoho_crm', status: 'enabled',
                                  settings: { client_id: 'old-id', client_secret: 'old-secret', refresh_token: 'old-rt',
                                              datacenter: 'com', webhook_secret: 'keep-me' })
        # zoho_org_key vive fuera de settings_json_schema (additionalProperties: false) -- se agrega
        # vía update_columns, igual que ZohoCrmController#fetch_or_cache_org_key en el código real,
        # para simular un hook que ya lo tenía cacheado sin violar la validación al crearlo aquí.
        h.update_columns(settings: h.settings.merge('zoho_org_key' => 'org123')) # rubocop:disable Rails/SkipsModelValidations
        h
      end

      before do
        stash_pending!
        stub_request(:post, %r{\Ahttps://accounts\.zoho\.com/oauth/v2/token})
          .to_return(status: 200, body: { access_token: 'at', refresh_token: 'new-rt' }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'updates the existing hook in place instead of creating a second one' do
        expect do
          get '/zoho_crm/callback', params: { code: oauth_code, state: state }
        end.not_to change(Integrations::Hook, :count)

        hook.reload
        expect(hook.settings['refresh_token']).to eq('new-rt')
        expect(hook.settings['client_id']).to eq('zoho-client-id')
      end

      it 'preserves webhook_secret but drops non-schema keys like a stale zoho_org_key' do
        get '/zoho_crm/callback', params: { code: oauth_code, state: state }

        hook.reload
        expect(hook.settings['webhook_secret']).to eq('keep-me')
        expect(hook.settings).not_to have_key('zoho_org_key')
      end

      it 'invalidates the cached access token for the old refresh_token' do
        expect_any_instance_of(Crm::Zoho::TokenRefreshService).to receive(:invalidate!) # rubocop:disable RSpec/AnyInstance

        get '/zoho_crm/callback', params: { code: oauth_code, state: state }
      end
    end
  end
end
