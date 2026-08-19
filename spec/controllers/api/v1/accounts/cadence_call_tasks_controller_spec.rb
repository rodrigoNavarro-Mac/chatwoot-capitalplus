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
  let(:cadence_definition) { create_cadence_definition!(whatsapp_inbox) }
  let(:enrollment) do
    CadenceEnrollment.create!(
      account: account, conversation: conversation, contact: contact, inbox: whatsapp_inbox,
      cadence_definition: cadence_definition, assignee_id: agent.id
    )
  end
  let!(:call_task) do
    CadenceCallTask.create!(account: account, cadence_enrollment: enrollment, conversation: conversation, user: agent, step: 1)
  end

  describe 'GET /api/v1/accounts/{account.id}/cadence_call_tasks' do
    it 'only returns own tasks to a non-admin agent' do
      get "/api/v1/accounts/#{account.id}/cadence_call_tasks", headers: other_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to be_empty
    end

    context 'when the requester has a custom role with cadence_view' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['cadence_view']) }
      let(:team) { create(:team, account: account) }
      let(:team_conversation) do
        create(:conversation, :with_team, account: account, inbox: whatsapp_inbox, team: team, contact: contact)
      end
      let!(:teammate_task) do
        CadenceCallTask.create!(
          account: account, cadence_enrollment: CadenceEnrollment.create!(
            account: account, conversation: team_conversation, contact: contact, inbox: whatsapp_inbox,
            cadence_definition: cadence_definition
          ), conversation: team_conversation, user: other_agent, step: 1
        )
      end

      before do
        other_agent.account_users.find_by(account: account).update!(custom_role: custom_role)
        create(:team_member, team: team, user: other_agent)
      end

      it 'includes tasks from the agent\'s team even when they are assigned to someone else' do
        get "/api/v1/accounts/#{account.id}/cadence_call_tasks", headers: other_agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.pluck('id')).to contain_exactly(teammate_task.id)
      end
    end

    context 'when the requester has a custom role with cadence_manage' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['cadence_manage']) }

      before { other_agent.account_users.find_by(account: account).update!(custom_role: custom_role) }

      it 'returns every task in the account, not just their own' do
        get "/api/v1/accounts/#{account.id}/cadence_call_tasks", headers: other_agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.pluck('id')).to contain_exactly(call_task.id)
      end
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
