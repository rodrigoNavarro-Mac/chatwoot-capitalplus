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

    it 'returns not_eligible when the conversation has no assignee' do
      other_conversation.update!(assignee: nil)

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
end
