require 'rails_helper'

RSpec.describe 'Quotes API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/{account.id}/quotes' do
    it 'includes who generated each quote' do
      create(:quote, account: account, generated_by: agent)

      get "/api/v1/accounts/#{account.id}/quotes", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body.first[:generated_by_name]).to eq(agent.available_name)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/quotes/{id}/authorize' do
    it 'approves a pending quote and notifies the owner only now, not before' do
      quote = create(:quote, account: account, status: 'completed', authorization_status: 'pending',
                             source_type: 'deal', zoho_deal_id: 'D1', deal_snapshot: { 'Owner' => { 'email' => 'owner@example.com' } })

      expect do
        post "/api/v1/accounts/#{account.id}/quotes/#{quote.id}/authorize", headers: administrator.create_new_auth_token, as: :json
      end.to have_enqueued_job(Quotes::NotifyOwnerJob).with(quote.id)

      expect(response).to have_http_status(:success)
      expect(quote.reload).to be_authorization_status_approved
      expect(quote.authorized_by).to eq(administrator)
    end

    it 'refuses to approve a quote that is not pending' do
      quote = create(:quote, account: account, status: 'completed', authorization_status: 'not_required')

      expect do
        post "/api/v1/accounts/#{account.id}/quotes/#{quote.id}/authorize", headers: administrator.create_new_auth_token, as: :json
      end.not_to have_enqueued_job(Quotes::NotifyOwnerJob)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/quotes/{id}' do
    it 'deletes a failed quote' do
      quote = create(:quote, :failed, account: account)

      delete "/api/v1/accounts/#{account.id}/quotes/#{quote.id}", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(Quote.exists?(quote.id)).to be false
    end

    it 'refuses to delete a completed quote' do
      quote = create(:quote, account: account, status: 'completed')

      delete "/api/v1/accounts/#{account.id}/quotes/#{quote.id}", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Quote.exists?(quote.id)).to be true
    end

    it 'allows agents to delete their own failed quotes' do
      quote = create(:quote, :failed, account: account)

      delete "/api/v1/accounts/#{account.id}/quotes/#{quote.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
    end
  end
end
