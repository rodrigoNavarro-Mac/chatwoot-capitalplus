require 'rails_helper'

RSpec.describe 'Zoho CRM Integration API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  before { account.enable_features!('crm_integration') }

  describe 'POST /api/v1/accounts/{account.id}/integrations/zoho_crm/sync_deals' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/integrations/zoho_crm/sync_deals"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the account has no Zoho CRM hook connected' do
      it 'returns not_found without enqueuing the job' do
        expect do
          post "/api/v1/accounts/#{account.id}/integrations/zoho_crm/sync_deals", headers: admin.create_new_auth_token, as: :json
        end.not_to have_enqueued_job(Crm::Zoho::DealsSyncJob)

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the account has Zoho CRM connected' do
      before do
        create(:integrations_hook, :zoho_crm, account: account, status: 'enabled')
      end

      it 'enqueues the sync job scoped to this account' do
        expect do
          post "/api/v1/accounts/#{account.id}/integrations/zoho_crm/sync_deals", headers: admin.create_new_auth_token, as: :json
        end.to have_enqueued_job(Crm::Zoho::DealsSyncJob).with(account.id)

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['success']).to be(true)
      end
    end
  end
end
