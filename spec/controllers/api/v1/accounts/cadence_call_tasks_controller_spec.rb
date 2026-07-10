require 'rails_helper'

RSpec.describe 'Cadence Call Tasks API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, assignee: agent, status: 'open')
  end
  let(:enrollment) do
    CadenceEnrollment.create!(account: account, conversation: conversation, contact: contact, inbox: whatsapp_inbox, assignee_id: agent.id)
  end
  let!(:call_task) do
    CadenceCallTask.create!(account: account, cadence_enrollment: enrollment, conversation: conversation, user: agent, step: 1)
  end

  describe 'GET /api/v1/accounts/{account.id}/cadence_call_tasks' do
    it 'only returns own tasks to a non-admin agent' do
      get "/api/v1/accounts/#{account.id}/cadence_call_tasks", headers: other_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)).to be_empty
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/cadence_call_tasks/:id/complete' do
    it 'allows the assigned agent to complete their own task' do
      post "/api/v1/accounts/#{account.id}/cadence_call_tasks/#{call_task.id}/complete",
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(call_task.reload.status).to eq('completed')
    end

    it 'forbids a different agent from completing someone else\'s task' do
      post "/api/v1/accounts/#{account.id}/cadence_call_tasks/#{call_task.id}/complete",
           headers: other_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
