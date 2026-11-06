require 'rails_helper'

RSpec.describe 'Campaigns API', type: :request do
  let(:account) { create(:account) }

  describe 'GET /api/v1/accounts/{account.id}/campaigns' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/campaigns"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }
      let(:inbox) { create(:inbox, account: account) }
      let!(:campaign) { create(:campaign, account: account, inbox: inbox, trigger_rules: { url: 'https://test.com' }) }

      it 'returns unauthorized for agents' do
        get "/api/v1/accounts/#{account.id}/campaigns",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns all campaigns to administrators' do
        get "/api/v1/accounts/#{account.id}/campaigns",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body.first[:id]).to eq(campaign.display_id)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/campaigns/:id' do
    let(:campaign) { create(:campaign, account: account, trigger_rules: { url: 'https://test.com' }) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for agents' do
        get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'shows the campaign for administrators' do
        get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body, symbolize_names: true)[:id]).to eq(campaign.display_id)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/campaigns' do
    let(:inbox) { create(:inbox, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/campaigns",
             params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for agents' do
        post "/api/v1/accounts/#{account.id}/campaigns",
             params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'creates a new campaign' do
        post "/api/v1/accounts/#{account.id}/campaigns",
             params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body, symbolize_names: true)[:title]).to eq('test')
      end

      it 'creates a new ongoing campaign' do
        post "/api/v1/accounts/#{account.id}/campaigns",
             params: { inbox_id: inbox.id, title: 'test', message: 'test message', trigger_rules: { url: 'https://test.com' } },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body, symbolize_names: true)[:title]).to eq('test')
      end

      it 'throws error when invalid url provided for ongoing campaign' do
        post "/api/v1/accounts/#{account.id}/campaigns",
             params: { inbox_id: inbox.id, title: 'test', message: 'test message', trigger_rules: { url: 'javascript' } },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'creates a new oneoff campaign' do
        twilio_sms = create(:channel_twilio_sms, account: account)
        twilio_inbox = create(:inbox, channel: twilio_sms, account: account)
        label1 = create(:label, account: account)
        label2 = create(:label, account: account)
        scheduled_at = 2.days.from_now

        post "/api/v1/accounts/#{account.id}/campaigns",
             params: {
               inbox_id: twilio_inbox.id, title: 'test', message: 'test message',
               scheduled_at: scheduled_at,
               audience: [{ type: 'Label', id: label1.id }, { type: 'Label', id: label2.id }]
             },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        response_data = JSON.parse(response.body, symbolize_names: true)
        expect(response_data[:campaign_type]).to eq('one_off')
        expect(response_data[:scheduled_at].present?).to be true
        expect(response_data[:scheduled_at]).to eq(scheduled_at.to_i)
        expect(response_data[:audience].pluck(:id)).to include(label1.id, label2.id)
      end

      it 'creates an A/B test campaign with a second template and a split' do
        label = create(:label, account: account)

        post "/api/v1/accounts/#{account.id}/campaigns",
             params: {
               inbox_id: inbox.id, title: 'ab', message: 'Texto A', scheduled_at: 2.days.from_now,
               audience: [{ type: 'Label', id: label.id }],
               template_params: { name: 'promo_a', language: 'es_MX', processed_params: { body: { '1' => 'x' } } },
               template_variant_b: { message: 'Texto B',
                                     template_params: { name: 'promo_b', language: 'es_MX', processed_params: { body: { '1' => 'y' } } } },
               ab_split: 60
             },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        data = response.parsed_body
        expect(data['ab_split']).to eq(60)
        expect(data['template_variant_b']).to include('message' => 'Texto B')
        expect(data['template_variant_b']['template_params']).to include('name' => 'promo_b', 'processed_params' => { 'body' => { '1' => 'y' } })
      end

      it 'rejects a split that leaves one template without recipients' do
        post "/api/v1/accounts/#{account.id}/campaigns",
             params: { inbox_id: inbox.id, title: 'ab', message: 'Texto A', ab_split: 100 },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/campaigns/:id' do
    let(:inbox) { create(:inbox, account: account) }
    let!(:campaign) { create(:campaign, account: account, trigger_rules: { url: 'https://test.com' }) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
              params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for agents' do
        patch "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
              params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'updates the campaign' do
        patch "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
              params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body, symbolize_names: true)[:title]).to eq('test')
      end

      it 'accepts a timezone' do
        # timezone solo se sirve en la respuesta para campanas one_off (ver
        # app/views/api/v1/models/_campaign.json.jbuilder) — una ongoing no tiene ventana
        # de envio, asi que el campo no aplica para ese tipo. campaign_type no se puede fijar
        # a mano: Campaign#ensure_correct_campaign_attributes (before_validation) lo deriva
        # del tipo de inbox en cada save/update (Whatsapp/Sms/Twilio SMS -> one_off, cualquier
        # otro -> ongoing) — hace falta un inbox de whatsapp, tanto al crear como en el PATCH.
        whatsapp_inbox = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
        one_off_campaign = create(:campaign, account: account, inbox: whatsapp_inbox)
        patch "/api/v1/accounts/#{account.id}/campaigns/#{one_off_campaign.display_id}",
              params: { inbox_id: whatsapp_inbox.id, title: 'test', message: 'test message', timezone: 'America/Mexico_City' },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body, symbolize_names: true)[:timezone]).to eq('America/Mexico_City')
      end

      it 'turns an A/B test off when template_variant_b is sent as null' do
        ab_campaign = create(:campaign, account: account, inbox: inbox, trigger_rules: { url: 'https://test.com' },
                                        template_variant_b: { 'template_params' => { 'name' => 'promo_b' }, 'message' => 'B' })

        patch "/api/v1/accounts/#{account.id}/campaigns/#{ab_campaign.display_id}",
              params: { title: 'sin prueba', template_variant_b: nil },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(ab_campaign.reload.template_variant_b).to be_nil
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/campaigns/:id/pause' do
    let(:inbox) { create(:inbox, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        campaign = create(:campaign, account: account, inbox: inbox, campaign_status: :processing)

        post "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/pause", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for agents' do
        campaign = create(:campaign, account: account, inbox: inbox, campaign_status: :processing)

        post "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/pause",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'pauses a processing campaign and cancels its pending sends' do
        campaign = create(:campaign, account: account, inbox: inbox, campaign_status: :processing)

        expect do
          post "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/pause",
               headers: administrator.create_new_auth_token,
               as: :json
        end.to have_enqueued_job(Campaigns::CancelScheduledJobsJob).with(campaign.id)

        expect(response).to have_http_status(:success)
        expect(campaign.reload.paused?).to be true
      end

      it 'pauses a completed campaign and cancels its pending sends' do
        # OneoffCampaignService marks the campaign completed right after scheduling every
        # delayed job, well before those jobs actually fire, so this is the state a
        # campaign sits in for most of its real send window.
        campaign = create(:campaign, account: account, inbox: inbox, campaign_status: :completed)

        expect do
          post "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/pause",
               headers: administrator.create_new_auth_token,
               as: :json
        end.to have_enqueued_job(Campaigns::CancelScheduledJobsJob).with(campaign.id)

        expect(response).to have_http_status(:success)
        expect(campaign.reload.paused?).to be true
      end

      it 'returns unprocessable_entity when the campaign is not running' do
        campaign = create(:campaign, account: account, inbox: inbox, campaign_status: :active)

        post "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/pause",
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(campaign.reload.active?).to be true
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/campaigns/:id/resume' do
    let(:inbox) { create(:inbox, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        campaign = create(:campaign, account: account, inbox: inbox, campaign_status: :paused)

        post "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/resume", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for agents' do
        campaign = create(:campaign, account: account, inbox: inbox, campaign_status: :paused)

        post "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/resume",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'resumes a paused campaign' do
        campaign = create(:campaign, account: account, inbox: inbox, campaign_status: :paused)

        expect do
          post "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/resume",
               headers: administrator.create_new_auth_token,
               as: :json
        end.to have_enqueued_job(Campaigns::ResumeCampaignJob).with(campaign.id)

        expect(response).to have_http_status(:success)
        expect(campaign.reload.processing?).to be true
      end

      it 'returns unprocessable_entity when the campaign is not paused' do
        campaign = create(:campaign, account: account, inbox: inbox, campaign_status: :active)

        post "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/resume",
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(campaign.reload.active?).to be true
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/campaigns/csv_preview' do
    let(:administrator) { create(:user, account: account, role: :administrator) }
    let(:csv_file) do
      Rack::Test::UploadedFile.new(
        StringIO.new("phone_number,name\n5215512345678,Ana\n,SinTelefono\n"), 'text/csv', original_filename: 'audience.csv'
      )
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/campaigns/csv_preview",
             params: { csv_audience: csv_file }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized for agents' do
        post "/api/v1/accounts/#{account.id}/campaigns/csv_preview",
             params: { csv_audience: csv_file },
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns validation stats for administrators' do
        post "/api/v1/accounts/#{account.id}/campaigns/csv_preview",
             params: { csv_audience: csv_file },
             headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:valid]).to be true
        expect(body[:total_rows]).to eq(2)
        expect(body[:valid_count]).to eq(1)
        expect(body[:missing_phone_count]).to eq(1)
      end

      it 'returns an error when no file is sent' do
        post "/api/v1/accounts/#{account.id}/campaigns/csv_preview",
             headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:valid]).to be false
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/campaigns/segment_contacts' do
    let(:administrator) { create(:user, account: account, role: :administrator) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:segment) do
      create(:custom_filter, account: account, user: administrator, filter_type: :contact,
                             query: { payload: [{ attribute_key: 'last_replied_at', filter_operator: 'is_not_present',
                                                  values: [], query_operator: nil }] })
    end

    it 'returns unauthorized for agents' do
      get "/api/v1/accounts/#{account.id}/campaigns/segment_contacts",
          params: { custom_filter_id: segment.id }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists the segment members matching the search' do
      ana = create(:contact, account: account, name: 'Ana López', phone_number: '+525511110001')
      create(:contact, account: account, name: 'Beto', phone_number: '+525511110002')

      get "/api/v1/accounts/#{account.id}/campaigns/segment_contacts",
          params: { custom_filter_id: segment.id, q: 'ana' }, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['meta']['count']).to eq(1)
      expect(response.parsed_body['payload']).to contain_exactly(include('id' => ana.id, 'phone_number' => '+525511110001'))
    end

    it 'does not expose segments of another account' do
      other_segment = create(:custom_filter, filter_type: :contact, query: { payload: [] })

      get "/api/v1/accounts/#{account.id}/campaigns/segment_contacts",
          params: { custom_filter_id: other_segment.id }, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/campaigns/segment_preview' do
    let(:administrator) { create(:user, account: account, role: :administrator) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:segment) do
      create(:custom_filter, account: account, user: administrator, filter_type: :contact,
                             query: { payload: [{ attribute_key: 'last_replied_at', filter_operator: 'is_not_present',
                                                  values: [], query_operator: nil }] })
    end

    it 'returns unauthorized for agents' do
      get "/api/v1/accounts/#{account.id}/campaigns/segment_preview",
          params: { custom_filter_id: segment.id }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the audience counts for administrators' do
      create(:contact, :with_phone_number, account: account)
      create(:contact, account: account, email: 'nophone@example.com')

      get "/api/v1/accounts/#{account.id}/campaigns/segment_preview",
          params: { custom_filter_id: segment.id }, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['total']).to eq(2)
      expect(body['eligible']).to eq(1)
      expect(body['excluded']['no_phone']).to eq(1)
    end

    it 'applies the contacts removed and added in the form before saving' do
      removed = create(:contact, :with_phone_number, account: account)
      create(:contact, :with_phone_number, account: account)

      get "/api/v1/accounts/#{account.id}/campaigns/segment_preview",
          params: { custom_filter_id: segment.id, exclude_ids: [removed.id] }, headers: administrator.create_new_auth_token

      expect(response.parsed_body).to include('total' => 1, 'eligible' => 1, 'removed' => 1)
    end

    it 'does not expose segments of another account' do
      other_segment = create(:custom_filter, filter_type: :contact, query: { payload: [] })

      get "/api/v1/accounts/#{account.id}/campaigns/segment_preview",
          params: { custom_filter_id: other_segment.id }, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/campaigns/:id' do
    let(:inbox) { create(:inbox, account: account) }
    let!(:campaign) { create(:campaign, account: account, trigger_rules: { url: 'https://test.com' }) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'return unauthorized if agent' do
        delete "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'delete campaign if admin' do
        delete "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
               headers: administrator.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(Campaign.exists?(campaign.display_id)).to be false
      end
    end
  end
end
