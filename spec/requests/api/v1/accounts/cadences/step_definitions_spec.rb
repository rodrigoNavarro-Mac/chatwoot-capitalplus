require 'rails_helper'

RSpec.describe 'Cadence Step Definitions API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:cadence_definition) do
    CadenceDefinition.create!(account: account, inbox: whatsapp_inbox, name: 'Cadencia de prueba', is_default: true)
  end

  let!(:step_one) do
    CadenceStepDefinition.create!(
      cadence_definition: cadence_definition, position: 1, template_key: 'wa_primer_contacto',
      template_name: 'cadencia_primer_contacto', template_language: 'es_MX', schedule_type: 'immediate', wait_window_minutes: 15
    )
  end
  let!(:step_two) do
    CadenceStepDefinition.create!(
      cadence_definition: cadence_definition, position: 2, template_key: 'wa_segundo_intento',
      template_name: 'cadencia_segundo_intento', template_language: 'es_MX', schedule_type: 'offset_from_last_step',
      offset_minutes: 300, wait_window_minutes: 120
    )
  end

  describe 'GET /api/v1/accounts/{account.id}/cadences/step_definitions' do
    it 'returns the steps ordered by position for administrators' do
      get "/api/v1/accounts/#{account.id}/cadences/step_definitions",
          params: { cadence_definition_id: cadence_definition.id }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body.map { |entry| entry['position'] }).to eq([1, 2])
    end

    it 'forbids a non-admin agent' do
      get "/api/v1/accounts/#{account.id}/cadences/step_definitions",
          params: { cadence_definition_id: cadence_definition.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/cadences/step_definitions' do
    it 'creates a new step at the end, auto-generating a template_key' do
      post "/api/v1/accounts/#{account.id}/cadences/step_definitions",
           params: {
             cadence_definition_id: cadence_definition.id, template_name: 'cadencia_nueva', template_language: 'es_MX',
             schedule_type: 'immediate', wait_window_minutes: 60
           },
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      new_step = body.find { |entry| entry['template_name'] == 'cadencia_nueva' }
      expect(new_step['position']).to eq(3)
      expect(new_step['template_key']).to be_present
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/cadences/step_definitions/:id' do
    it 'updates the schedule and media of a step' do
      patch "/api/v1/accounts/#{account.id}/cadences/step_definitions/#{step_one.id}",
            params: {
              cadence_definition_id: cadence_definition.id, wait_window_minutes: 30,
              media_url: 'https://cdn.example.com/v.mp4', media_type: 'video'
            },
            headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(step_one.reload.wait_window_minutes).to eq(30)
      expect(step_one.reload.media_url).to eq('https://cdn.example.com/v.mp4')
    end

    it 'updates the body_variables mapping' do
      patch "/api/v1/accounts/#{account.id}/cadences/step_definitions/#{step_one.id}",
            params: {
              cadence_definition_id: cadence_definition.id,
              body_variables: { '1' => '{{ contact.name }}' }
            },
            headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(step_one.reload.body_variables).to eq({ '1' => '{{ contact.name }}' })
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/cadences/step_definitions/:id' do
    it 'removes the step and renumbers the following steps' do
      delete "/api/v1/accounts/#{account.id}/cadences/step_definitions/#{step_one.id}",
             params: { cadence_definition_id: cadence_definition.id }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(CadenceStepDefinition.exists?(step_one.id)).to be(false)
      expect(step_two.reload.position).to eq(1)
    end

    it 'does not affect the steps_snapshot of an in-flight enrollment' do
      contact = create(:contact, account: account, phone_number: '+15551234567')
      conversation = create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, assignee: agent, status: 'open')
      account.enable_features!(:whatsapp_cadences)
      enrollment = Cadences::EnrollmentService.new(conversation: conversation).enroll!

      delete "/api/v1/accounts/#{account.id}/cadences/step_definitions/#{step_one.id}",
             params: { cadence_definition_id: cadence_definition.id }, headers: administrator.create_new_auth_token, as: :json

      expect(enrollment.reload.total_steps).to eq(2)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/cadences/step_definitions/reorder' do
    it 'reassigns positions based on the given order' do
      patch "/api/v1/accounts/#{account.id}/cadences/step_definitions/reorder",
            params: { cadence_definition_id: cadence_definition.id, ordered_ids: [step_two.id, step_one.id] },
            headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(step_two.reload.position).to eq(1)
      expect(step_one.reload.position).to eq(2)
    end
  end
end
