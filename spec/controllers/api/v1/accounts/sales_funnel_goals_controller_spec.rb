require 'rails_helper'

RSpec.describe 'Sales Funnel Goals API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  describe 'GET /api/v1/accounts/{account.id}/sales_funnel_goals' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/sales_funnel_goals"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let!(:goal) { create(:sales_funnel_goal, account: account, development_key: 'torre-1', stage: 'leads') }

      it 'returns the goals for the account' do
        create(:sales_funnel_goal, account: account, development_key: 'torre-2', stage: 'leads')

        get "/api/v1/accounts/#{account.id}/sales_funnel_goals", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.count).to eq(2)
      end

      it 'filters by development_key' do
        create(:sales_funnel_goal, account: account, development_key: 'torre-2', stage: 'leads')

        get "/api/v1/accounts/#{account.id}/sales_funnel_goals",
            params: { development_key: 'torre-1' },
            headers: admin.create_new_auth_token,
            as: :json

        response_body = response.parsed_body
        expect(response_body.count).to eq(1)
        expect(response_body.first['id']).to eq(goal.id)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/sales_funnel_goals' do
    let(:payload) do
      { development_key: 'torre-1', stage: 'leads', period_month: '2026-07-01', target_percent: 40 }
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        expect do
          post "/api/v1/accounts/#{account.id}/sales_funnel_goals", params: payload
        end.not_to change(SalesFunnelGoal, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator' do
      it 'creates the goal' do
        expect do
          post "/api/v1/accounts/#{account.id}/sales_funnel_goals", headers: admin.create_new_auth_token, params: payload
        end.to change(SalesFunnelGoal, :count).by(1)

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response.last['development_key']).to eq('torre-1')
        expect(json_response.last['target_percent']).to eq('40.0')
      end
    end

    context 'when it is an agent' do
      it 'returns unauthorized and does not create the goal' do
        expect do
          post "/api/v1/accounts/#{account.id}/sales_funnel_goals", headers: agent.create_new_auth_token, params: payload
        end.not_to change(SalesFunnelGoal, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when target_percent is out of range' do
      it 'returns unprocessable_entity' do
        post "/api/v1/accounts/#{account.id}/sales_funnel_goals",
             headers: admin.create_new_auth_token,
             params: payload.merge(target_percent: 150)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/sales_funnel_goals/:id' do
    let!(:goal) { create(:sales_funnel_goal, account: account, target_percent: 20) }

    context 'when it is an administrator' do
      it 'updates the goal' do
        patch "/api/v1/accounts/#{account.id}/sales_funnel_goals/#{goal.id}",
              headers: admin.create_new_auth_token,
              params: { target_percent: 60 },
              as: :json

        expect(response).to have_http_status(:success)
        expect(goal.reload.target_percent).to eq(60)
      end
    end

    context 'when it is an agent' do
      it 'returns unauthorized and does not update the goal' do
        patch "/api/v1/accounts/#{account.id}/sales_funnel_goals/#{goal.id}",
              headers: agent.create_new_auth_token,
              params: { target_percent: 60 },
              as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(goal.reload.target_percent).to eq(20)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/sales_funnel_goals/:id' do
    let!(:goal) { create(:sales_funnel_goal, account: account) }

    context 'when it is an administrator' do
      it 'deletes the goal' do
        delete "/api/v1/accounts/#{account.id}/sales_funnel_goals/#{goal.id}", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:no_content)
        expect(account.sales_funnel_goals.count).to eq(0)
      end
    end

    context 'when it is an agent' do
      it 'returns unauthorized and does not delete the goal' do
        delete "/api/v1/accounts/#{account.id}/sales_funnel_goals/#{goal.id}", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(account.sales_funnel_goals.count).to eq(1)
      end
    end
  end
end
