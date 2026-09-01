require 'rails_helper'

RSpec.describe 'Call Analyses API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent_role) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:call) { create(:call, account: account, conversation: conversation, accepted_by_agent: agent, provider: :aircall, status: 'completed') }

  describe 'GET /api/v1/accounts/{account.id}/call_analyses' do
    it 'returns unauthorized for agents' do
      get "/api/v1/accounts/#{account.id}/call_analyses", headers: agent_role.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns failed/low-confidence analyses to administrators' do
      failed = create(:call_analysis, call: call, agent: agent, status: 'failed', error_step: 'model_error')

      get "/api/v1/accounts/#{account.id}/call_analyses", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body.pluck(:id)).to eq([failed.id])
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/call_analyses/recent' do
    it 'returns the most recently analyzed completed calls, including the agent name' do
      analysis = create(:call_analysis, call: call, agent: agent, confidence: 'high')

      get "/api/v1/accounts/#{account.id}/call_analyses/recent", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body.first[:id]).to eq(analysis.id)
      expect(body.first[:agent_name]).to eq(agent.available_name)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/call_analyses/:id' do
    it 'returns the full analysis detail, including qualification map and the underlying call' do
      analysis = create(:call_analysis, call: call, agent: agent,
                                        qualification_map: { 'presupuesto' => { 'captured' => true, 'evidence' => 'cita' } },
                                        objections: [{ 'category' => 'financiera', 'quote' => 'está caro' }])

      get "/api/v1/accounts/#{account.id}/call_analyses/#{analysis.id}", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:id]).to eq(analysis.id)
      expect(body[:qualification_map]).to eq(presupuesto: { captured: true, evidence: 'cita' })
      expect(body[:objections]).to eq([{ category: 'financiera', quote: 'está caro' }])
      expect(body[:call][:id]).to eq(call.id)
    end

    it 'returns unauthorized for agents' do
      analysis = create(:call_analysis, call: call, agent: agent)

      get "/api/v1/accounts/#{account.id}/call_analyses/#{analysis.id}", headers: agent_role.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/call_analyses/:id/retry' do
    it 'enqueues AnalyzeJob for the same call_id' do
      analysis = create(:call_analysis, call: call, agent: agent, status: 'failed', error_step: 'model_error')

      expect { post "/api/v1/accounts/#{account.id}/call_analyses/#{analysis.id}/retry", headers: administrator.create_new_auth_token, as: :json }
        .to have_enqueued_job(CallAnalysis::AnalyzeJob).with(call.id)

      expect(response).to have_http_status(:success)
    end
  end
end
