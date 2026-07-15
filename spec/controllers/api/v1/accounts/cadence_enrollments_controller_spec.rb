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
end
