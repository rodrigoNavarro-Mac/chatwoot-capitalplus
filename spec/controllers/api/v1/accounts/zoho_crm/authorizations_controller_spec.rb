require 'rails_helper'

RSpec.describe 'ZohoCrm Authorization API', type: :request do
  let(:account) { create(:account) }
  let(:valid_params) { { client_id: 'zoho-client-id', client_secret: 'zoho-client-secret', datacenter: 'com' } }

  describe 'POST /api/v1/accounts/{account.id}/zoho_crm/authorization' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/zoho_crm/authorization", params: valid_params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for agent' do
        post "/api/v1/accounts/#{account.id}/zoho_crm/authorization",
             headers: agent.create_new_auth_token, params: valid_params, as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns unprocessable_entity when a required field is missing' do
        post "/api/v1/accounts/#{account.id}/zoho_crm/authorization",
             headers: administrator.create_new_auth_token, params: valid_params.except(:client_secret), as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns unprocessable_entity for an unknown datacenter' do
        post "/api/v1/accounts/#{account.id}/zoho_crm/authorization",
             headers: administrator.create_new_auth_token, params: valid_params.merge(datacenter: 'ru'), as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      describe 'a successful request' do
        subject(:parsed_url) do
          post "/api/v1/accounts/#{account.id}/zoho_crm/authorization",
               headers: administrator.create_new_auth_token, params: valid_params, as: :json
          CGI.parse(URI.parse(response.parsed_body['url']).query)
        end

        it 'returns success' do
          parsed_url
          expect(response).to have_http_status(:success)
        end

        it 'points at the Zoho authorize endpoint with offline access and consent forced' do
          expect(parsed_url['response_type']).to eq(['code'])
          expect(parsed_url['access_type']).to eq(['offline'])
          expect(parsed_url['prompt']).to eq(['consent'])
        end

        it 'carries the client_id, the callback redirect_uri, and the full CRM scope' do
          expect(parsed_url['client_id']).to eq(['zoho-client-id'])
          expect(parsed_url['redirect_uri']).to eq(["#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/zoho_crm/callback"])
          expect(parsed_url['scope'].first).to include('ZohoCRM.modules.ALL')
        end

        it 'signs a state that resolves back to the account' do
          state = parsed_url['state'].first
          expect(GlobalID::Locator.locate_signed(state, for: 'default')).to eq(account)
        end

        it 'stashes the pending client_id/secret/datacenter in Redis under that state' do
          state = parsed_url['state'].first
          pending = JSON.parse(Redis::Alfred.get(format(Redis::Alfred::ZOHO_CRM_PENDING_OAUTH, state: state)))
          expect(pending).to eq('client_id' => 'zoho-client-id', 'client_secret' => 'zoho-client-secret', 'datacenter' => 'com')
        end
      end

      it 'builds the authorize URL against the requested datacenter' do
        post "/api/v1/accounts/#{account.id}/zoho_crm/authorization",
             headers: administrator.create_new_auth_token, params: valid_params.merge(datacenter: 'eu'), as: :json

        expect(response.parsed_body['url']).to start_with('https://accounts.zoho.eu/oauth/v2/auth')
      end
    end
  end
end
