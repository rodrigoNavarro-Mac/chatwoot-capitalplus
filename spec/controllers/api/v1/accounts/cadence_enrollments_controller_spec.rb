require 'rails_helper'

RSpec.describe 'Cadence Enrollments API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, assignee: agent, status: 'open')
  end
  let(:cadence_definition) { create_cadence_definition!(whatsapp_inbox) }
  let!(:enrollment) do
    CadenceEnrollment.create!(
      account: account, conversation: conversation, contact: contact, inbox: whatsapp_inbox,
      cadence_definition: cadence_definition, assignee_id: agent.id
    )
  end

  before { account.enable_features!(:whatsapp_cadences) }

  describe 'GET /api/v1/accounts/{account.id}/cadence_enrollments' do
    it 'returns unauthorized for agents' do
      get "/api/v1/accounts/#{account.id}/cadence_enrollments", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the enrollments for administrators' do
      get "/api/v1/accounts/#{account.id}/cadence_enrollments", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body.first[:id]).to eq(enrollment.id)
    end

    it 'includes the cadence definition (variant) of each enrollment' do
      get "/api/v1/accounts/#{account.id}/cadence_enrollments", headers: administrator.create_new_auth_token, as: :json

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body.first[:cadence_definition][:id]).to eq(cadence_definition.id)
      expect(body.first[:cadence_definition][:name]).to eq(cadence_definition.name)
    end

    it 'filters by cadence_definition_id' do
      other_definition = create_cadence_definition!(whatsapp_inbox, is_default: false, name: 'Other variant')
      other_contact = create(:contact, account: account, phone_number: '+15557654321')
      other_conversation = create(:conversation, account: account, inbox: whatsapp_inbox, contact: other_contact, assignee: agent, status: 'open')
      CadenceEnrollment.create!(
        account: account, conversation: other_conversation, contact: other_contact, inbox: whatsapp_inbox,
        cadence_definition: other_definition, assignee_id: agent.id
      )

      get "/api/v1/accounts/#{account.id}/cadence_enrollments",
          params: { cadence_definition_id: other_definition.id }, headers: administrator.create_new_auth_token, as: :json

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body.size).to eq(1)
      expect(body.first[:cadence_definition][:id]).to eq(other_definition.id)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/cadence_enrollments/:id/cancel' do
    it 'cancels the enrollment for administrators' do
      post "/api/v1/accounts/#{account.id}/cadence_enrollments/#{enrollment.id}/cancel",
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(enrollment.reload.status).to eq('failed')
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/cadence_enrollments/:id/pause' do
    it 'pauses the enrollment for administrators' do
      post "/api/v1/accounts/#{account.id}/cadence_enrollments/#{enrollment.id}/pause",
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(enrollment.reload.status).to eq('paused_by_response')
      expect(enrollment.stopped_reason).to eq('manual_pause')
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/cadence_enrollments/:id/resume' do
    before { enrollment.update!(status: :failed, stopped_reason: 'send_failed', next_action_at: 2.days.ago) }

    it 'reactivates a failed enrollment, clears stopped_reason and refreshes next_action_at' do
      post "/api/v1/accounts/#{account.id}/cadence_enrollments/#{enrollment.id}/resume",
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      enrollment.reload
      expect(enrollment.status).to eq('active')
      expect(enrollment.stopped_reason).to be_nil
      expect(enrollment.next_action_at).to be_within(5.seconds).of(Time.current)
    end

    it 'enqueues Cadences::AdvanceJob for the enrollment' do
      expect do
        post "/api/v1/accounts/#{account.id}/cadence_enrollments/#{enrollment.id}/resume",
             headers: administrator.create_new_auth_token, as: :json
      end.to have_enqueued_job(Cadences::AdvanceJob).with(enrollment.id)
    end

    it 'refreshes steps_snapshot from the live cadence definition (a fixed media_url/media_type must take effect on retry)' do
      expect(enrollment.steps_snapshot).to eq([])

      post "/api/v1/accounts/#{account.id}/cadence_enrollments/#{enrollment.id}/resume",
           headers: administrator.create_new_auth_token, as: :json

      enrollment.reload
      expect(enrollment.steps_snapshot).not_to eq([])
      expect(enrollment.step_definition_for(1)[:template_name]).to eq(cadence_definition.cadence_step_definitions.find_by(position: 1).template_name)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/cadence_enrollments/:id/resume for a cold enrollment' do
    before do
      enrollment.update!(status: :cold, stopped_reason: 'no_response_after_cadence',
                         next_action_at: 2.days.ago, steps_snapshot: cadence_steps_snapshot(count: 2))
    end

    it 'reactivates and refreshes steps_snapshot so the enrollment picks up steps added after it went cold' do
      expect(enrollment.total_steps).to eq(2)

      post "/api/v1/accounts/#{account.id}/cadence_enrollments/#{enrollment.id}/resume",
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      enrollment.reload
      expect(enrollment.status).to eq('active')
      expect(enrollment.stopped_reason).to be_nil
      expect(enrollment.total_steps).to eq(cadence_definition.cadence_step_definitions.count)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/cadence_enrollments/retry_failed' do
    before { enrollment.update!(status: :failed, stopped_reason: 'no_next_step', next_action_at: 2.days.ago) }

    it 'reactivates every failed enrollment matching the current filters and refreshes next_action_at' do
      post "/api/v1/accounts/#{account.id}/cadence_enrollments/retry_failed",
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:retried]).to eq(1)

      enrollment.reload
      expect(enrollment.status).to eq('active')
      expect(enrollment.stopped_reason).to be_nil
      expect(enrollment.next_action_at).to be_within(5.seconds).of(Time.current)
    end

    it 'enqueues Cadences::AdvanceJob for each retried enrollment' do
      expect do
        post "/api/v1/accounts/#{account.id}/cadence_enrollments/retry_failed",
             headers: administrator.create_new_auth_token, as: :json
      end.to have_enqueued_job(Cadences::AdvanceJob).with(enrollment.id)
    end

    it 'does not touch enrollments that are not failed' do
      enrollment.update!(status: :active, stopped_reason: nil)

      post "/api/v1/accounts/#{account.id}/cadence_enrollments/retry_failed",
           headers: administrator.create_new_auth_token, as: :json

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:retried]).to eq(0)
    end

    it 'refreshes steps_snapshot from the live cadence definition (a fixed media_url/media_type must take effect on retry)' do
      expect(enrollment.steps_snapshot).to eq([])

      post "/api/v1/accounts/#{account.id}/cadence_enrollments/retry_failed",
           headers: administrator.create_new_auth_token, as: :json

      enrollment.reload
      expect(enrollment.steps_snapshot).not_to eq([])
      expect(enrollment.step_definition_for(1)[:template_name]).to eq(cadence_definition.cadence_step_definitions.find_by(position: 1).template_name)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/cadence_enrollments' do
    let(:other_contact) { create(:contact, account: account, phone_number: '+15557654321') }
    let(:other_conversation) do
      create(:conversation, account: account, inbox: whatsapp_inbox, contact: other_contact, assignee: agent, status: 'open')
    end

    it 'returns unauthorized for agents' do
      post "/api/v1/accounts/#{account.id}/cadence_enrollments",
           params: { conversation_id: other_conversation.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'enrolls an eligible conversation for administrators' do
      expect do
        post "/api/v1/accounts/#{account.id}/cadence_enrollments",
             params: { conversation_id: other_conversation.id }, headers: administrator.create_new_auth_token, as: :json
      end.to change(CadenceEnrollment, :count).by(1)

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:current_step]).to eq(0)
      expect(CadenceEnrollment.find_by(conversation_id: other_conversation.id)).to be_present
    end

    it 'returns already_enrolled when the conversation already has an enrollment' do
      post "/api/v1/accounts/#{account.id}/cadence_enrollments",
           params: { conversation_id: conversation.id }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body, symbolize_names: true)[:error]).to eq('already_enrolled')
    end

    it 'enrolls a conversation with no assignee (assignee is not required for eligibility)' do
      other_conversation.update!(assignee: nil)

      post "/api/v1/accounts/#{account.id}/cadence_enrollments",
           params: { conversation_id: other_conversation.id }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(CadenceEnrollment.find_by(conversation_id: other_conversation.id)).to be_present
    end

    it 'returns not_eligible when the whatsapp_cadences feature is disabled' do
      account.disable_features!(:whatsapp_cadences)

      post "/api/v1/accounts/#{account.id}/cadence_enrollments",
           params: { conversation_id: other_conversation.id }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body, symbolize_names: true)[:error]).to eq('not_eligible')
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/cadence_enrollments/eligible_conversations' do
    let(:other_contact) { create(:contact, account: account, name: 'Jane Doe', phone_number: '+15557654321') }
    let!(:other_conversation) do
      create(:conversation, account: account, inbox: whatsapp_inbox, contact: other_contact, assignee: agent, status: 'open')
    end

    it 'returns unauthorized for agents' do
      get "/api/v1/accounts/#{account.id}/cadence_enrollments/eligible_conversations",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists eligible conversations, excluding conversations already enrolled' do
      get "/api/v1/accounts/#{account.id}/cadence_enrollments/eligible_conversations",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body.pluck(:id)).to contain_exactly(other_conversation.id)
    end

    it 'filters by contact name' do
      get "/api/v1/accounts/#{account.id}/cadence_enrollments/eligible_conversations",
          params: { q: 'Jane' }, headers: administrator.create_new_auth_token, as: :json

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body.pluck(:id)).to contain_exactly(other_conversation.id)
    end

    it 'excludes conversations without an assignee' do
      other_conversation.update!(assignee: nil)

      get "/api/v1/accounts/#{account.id}/cadence_enrollments/eligible_conversations",
          headers: administrator.create_new_auth_token, as: :json

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body).to be_empty
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/cadence_enrollments/enroll_past_leads' do
    it 'returns unauthorized for agents' do
      post "/api/v1/accounts/#{account.id}/cadence_enrollments/enroll_past_leads",
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'enqueues Cadences::EnrollPastLeadsJob scoped to the account, with no inbox_id by default' do
      expect { post "/api/v1/accounts/#{account.id}/cadence_enrollments/enroll_past_leads", headers: administrator.create_new_auth_token, as: :json }
        .to have_enqueued_job(Cadences::EnrollPastLeadsJob).with(account.id, inbox_id: nil)

      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body, symbolize_names: true)).to eq(enqueued: true)
    end

    it 'passes inbox_id through when given' do
      expect do
        post "/api/v1/accounts/#{account.id}/cadence_enrollments/enroll_past_leads",
             params: { inbox_id: whatsapp_inbox.id }, headers: administrator.create_new_auth_token, as: :json
      end.to have_enqueued_job(Cadences::EnrollPastLeadsJob).with(account.id, inbox_id: whatsapp_inbox.id)
    end
  end
end
