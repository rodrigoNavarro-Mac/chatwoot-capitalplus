require 'rails_helper'

RSpec.describe 'Cadence Definitions API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }

  let!(:default_definition) do
    CadenceDefinition.create!(account: account, inbox: whatsapp_inbox, name: 'Default', is_default: true)
  end

  describe 'GET /api/v1/accounts/{account.id}/cadences/definitions' do
    it 'lists the cadence definitions for the inbox' do
      get "/api/v1/accounts/#{account.id}/cadences/definitions",
          params: { inbox_id: whatsapp_inbox.id }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body.first['name']).to eq('Default')
      expect(body.first['is_default']).to be(true)
    end

    it 'forbids a non-admin agent' do
      get "/api/v1/accounts/#{account.id}/cadences/definitions",
          params: { inbox_id: whatsapp_inbox.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/cadences/definitions' do
    it 'creates a new (non-default) cadence definition for a segment' do
      post "/api/v1/accounts/#{account.id}/cadences/definitions",
           params: { inbox_id: whatsapp_inbox.id, name: 'Inversión — A', segment_value: 'Inversión' },
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      created = body.find { |entry| entry['name'] == 'Inversión — A' }
      expect(created['segment_value']).to eq('Inversión')
      expect(created['is_default']).to be(false)
    end

    it 'unmarks the previous default when creating a new one marked as default' do
      post "/api/v1/accounts/#{account.id}/cadences/definitions",
           params: { inbox_id: whatsapp_inbox.id, name: 'New default', is_default: true },
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(default_definition.reload.is_default).to be(false)
      new_default = CadenceDefinition.find_by(name: 'New default')
      expect(new_default.is_default).to be(true)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/cadences/definitions/:id' do
    it 'updates the name and segment_value' do
      patch "/api/v1/accounts/#{account.id}/cadences/definitions/#{default_definition.id}",
            params: { name: 'Renamed', segment_value: 'Vivienda' },
            headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(default_definition.reload.name).to eq('Renamed')
      expect(default_definition.segment_value).to eq('Vivienda')
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/cadences/definitions/:id' do
    it 'deletes the cadence definition and its steps' do
      CadenceStepDefinition.create!(
        cadence_definition: default_definition, position: 1, template_key: 'wa_x', template_name: 'x',
        schedule_type: 'immediate', wait_window_minutes: 15
      )

      delete "/api/v1/accounts/#{account.id}/cadences/definitions/#{default_definition.id}",
             headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(CadenceDefinition.exists?(default_definition.id)).to be(false)
      expect(CadenceStepDefinition.count).to eq(0)
    end
  end
end
