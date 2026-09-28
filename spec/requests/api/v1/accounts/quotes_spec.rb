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
