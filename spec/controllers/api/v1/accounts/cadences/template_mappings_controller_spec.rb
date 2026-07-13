require 'rails_helper'

RSpec.describe 'Cadence Template Mappings API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }

  describe 'GET /api/v1/accounts/{account.id}/cadences/template_mappings' do
    it 'returns the fixed template keys with the default mapping when there is no override' do
      get "/api/v1/accounts/#{account.id}/cadences/template_mappings",
          params: { inbox_id: whatsapp_inbox.id },
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body.size).to eq(Cadences::StepDefinitions::STEPS.size)
      first_contact_entry = body.find { |entry| entry['template_key'] == 'wa_primer_contacto' }
      expect(first_contact_entry['name']).to eq('cadencia_primer_contacto')
      expect(first_contact_entry['is_custom']).to be(false)
    end

    it 'forbids a non-admin agent' do
      get "/api/v1/accounts/#{account.id}/cadences/template_mappings",
          params: { inbox_id: whatsapp_inbox.id },
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/cadences/template_mappings/bulk_update' do
    it 'creates overrides for the given inbox without touching the fixed step rules' do
      patch "/api/v1/accounts/#{account.id}/cadences/template_mappings/bulk_update",
            params: {
              inbox_id: whatsapp_inbox.id,
              mappings: [
                { template_key: 'wa_primer_contacto', name: 'cadencia_primer_contacto_torre_sur', language: 'es_MX' }
              ]
            },
            headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      mapping = CadenceTemplateMapping.find_by(inbox_id: whatsapp_inbox.id, template_key: 'wa_primer_contacto')
      expect(mapping.name).to eq('cadencia_primer_contacto_torre_sur')

      body = JSON.parse(response.body)
      updated_entry = body.find { |entry| entry['template_key'] == 'wa_primer_contacto' }
      expect(updated_entry['is_custom']).to be(true)
    end

    it 'rejects a template_key that is not one of the fixed cadence steps' do
      patch "/api/v1/accounts/#{account.id}/cadences/template_mappings/bulk_update",
            params: {
              inbox_id: whatsapp_inbox.id,
              mappings: [{ template_key: 'invented_step', name: 'x', language: 'es_MX' }]
            },
            headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/cadences/template_mappings/:template_key' do
    it 'removes the override and reverts to the default mapping' do
      CadenceTemplateMapping.create!(
        account: account, inbox: whatsapp_inbox, template_key: 'wa_primer_contacto',
        name: 'custom', language: 'es_MX'
      )

      delete "/api/v1/accounts/#{account.id}/cadences/template_mappings/wa_primer_contacto",
             params: { inbox_id: whatsapp_inbox.id },
             headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(CadenceTemplateMapping.find_by(inbox_id: whatsapp_inbox.id, template_key: 'wa_primer_contacto')).to be_nil
    end
  end
end
