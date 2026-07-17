require 'rails_helper'

RSpec.describe 'Webhooks::ZohoCrmController', type: :request do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { whatsapp_channel.inbox }
  let!(:agent_bot) { create(:agent_bot, account: account, bot_config: { 'variables' => { 'desarrollo' => 'torre-1' } }) }
  let(:base_params) do
    {
      phone: '2228442014',
      contact_name: 'Rodrigo',
      desarrollo: 'torre-1',
      template_name: 'test_no_params_template',
      template_language: 'en'
    }
  end

  let(:sent_requests) { [] }

  def post_send_template(params)
    post "/webhooks/zoho_crm/#{account.id}/send_template", params: params, as: :json
  end

  def last_sent_components
    JSON.parse(sent_requests.last.body)['template']['components']
  end

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
    stub_request(:post, /graph\.facebook\.com.*messages/).to_return do |request|
      sent_requests << request
      { status: 200, body: { messages: [{ id: 'wamid.zoho1' }] }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  describe 'POST /webhooks/zoho_crm/:account_id/send_template' do
    it 'sends a template with no header' do
      post_send_template(base_params)

      expect(response).to have_http_status(:ok)
      expect(last_sent_components.any? { |c| c['type'] == 'header' }).to be(false)
    end

    it 'sends a template with a text header' do
      post_send_template(base_params.merge(header: { type: 'text', text: 'Rodrigo' }))

      expect(response).to have_http_status(:ok)
      header = last_sent_components.find { |c| c['type'] == 'header' }
      expect(header['parameters']).to eq([{ 'type' => 'text', 'text' => 'Rodrigo' }])
    end

    it 'sends a template with an image header by URL' do
      post_send_template(base_params.merge(header: { type: 'image', link: 'https://dominio.com/imagen.png' }))

      expect(response).to have_http_status(:ok)
      header = last_sent_components.find { |c| c['type'] == 'header' }
      expect(header['parameters']).to eq([{ 'type' => 'image', 'image' => { 'link' => 'https://dominio.com/imagen.png' } }])
    end

    it 'sends a template with an image header by media id' do
      post_send_template(base_params.merge(header: { type: 'image', id: 'META_MEDIA_ID' }))

      expect(response).to have_http_status(:ok)
      header = last_sent_components.find { |c| c['type'] == 'header' }
      expect(header['parameters']).to eq([{ 'type' => 'image', 'image' => { 'id' => 'META_MEDIA_ID' } }])
    end

    it 'sends a template with a video header by URL' do
      post_send_template(base_params.merge(header: { type: 'video', link: 'https://dominio.com/video.mp4' }))

      expect(response).to have_http_status(:ok)
      header = last_sent_components.find { |c| c['type'] == 'header' }
      expect(header['parameters']).to eq([{ 'type' => 'video', 'video' => { 'link' => 'https://dominio.com/video.mp4' } }])
    end

    it 'sends a template with a document header with a filename' do
      post_send_template(base_params.merge(header: { type: 'document', link: 'https://dominio.com/Brochure.pdf', filename: 'Brochure.pdf' }))

      expect(response).to have_http_status(:ok)
      header = last_sent_components.find { |c| c['type'] == 'header' }
      expect(header['parameters']).to eq([{ 'type' => 'document',
                                            'document' => { 'link' => 'https://dominio.com/Brochure.pdf', 'filename' => 'Brochure.pdf' } }])
    end

    it 'sends a template with a document header without a filename' do
      post_send_template(base_params.merge(header: { type: 'document', link: 'https://dominio.com/Brochure.pdf' }))

      expect(response).to have_http_status(:ok)
      header = last_sent_components.find { |c| c['type'] == 'header' }
      expect(header['parameters'].first['document']).to eq({ 'link' => 'https://dominio.com/Brochure.pdf' })
    end

    it 'sends a template with a location header' do
      location = { type: 'location', latitude: 19.0414, longitude: -98.2063, name: 'Oficina Capital Plus', address: 'Puebla, México' }
      post_send_template(base_params.merge(header: location))

      expect(response).to have_http_status(:ok)
      header = last_sent_components.find { |c| c['type'] == 'header' }
      expect(header['parameters']).to eq([{
                                           'type' => 'location',
                                           'location' => { 'latitude' => 19.0414, 'longitude' => -98.2063, 'name' => 'Oficina Capital Plus',
                                                           'address' => 'Puebla, México' }
                                         }])
    end

    it 'accepts legacy positional string body_params' do
      post_send_template(base_params.merge(template_name: 'sample_shipping_confirmation', template_language: 'en_US', body_params: ['2']))

      expect(response).to have_http_status(:ok)
      body = last_sent_components.find { |c| c['type'] == 'body' }
      expect(body['parameters']).to eq([{ 'type' => 'text', 'text' => '2' }])
    end

    it 'accepts typed body_params' do
      post_send_template(base_params.merge(body_params: [{ type: 'text', text: 'Rodrigo' }]))

      expect(response).to have_http_status(:ok)
      body = last_sent_components.find { |c| c['type'] == 'body' }
      expect(body['parameters']).to eq([{ 'type' => 'text', 'text' => 'Rodrigo' }])
    end

    it 'accepts a dynamic quick_reply button' do
      post_send_template(base_params.merge(button_params: [{ type: 'quick_reply', index: 0, payload: 'CONFIRMAR_VISITA' }]))

      expect(response).to have_http_status(:ok)
      button = last_sent_components.find { |c| c['type'] == 'button' }
      expect(button['sub_type']).to eq('quick_reply')
      expect(button['parameters']).to eq([{ 'type' => 'payload', 'payload' => 'CONFIRMAR_VISITA' }])
    end

    it 'accepts a dynamic url button' do
      post_send_template(base_params.merge(button_params: [{ type: 'url', index: 1, text: 'lead-123' }]))

      expect(response).to have_http_status(:ok)
      button = last_sent_components.find { |c| c['type'] == 'button' }
      expect(button['sub_type']).to eq('url')
      expect(button['parameters']).to eq([{ 'type' => 'text', 'text' => 'lead-123' }])
    end

    it 'accepts a flow button' do
      button_params = [{ type: 'flow', index: 0, flow_token: 'TOKEN_DEL_FLUJO', flow_action_data: { lead_id: '6923204000024550001' } }]
      post_send_template(base_params.merge(button_params: button_params))

      expect(response).to have_http_status(:ok)
      button = last_sent_components.find { |c| c['type'] == 'button' }
      expect(button['sub_type']).to eq('flow')
      expect(button['parameters']).to eq([{ 'type' => 'action',
                                            'action' => { 'flow_token' => 'TOKEN_DEL_FLUJO',
                                                          'flow_action_data' => { 'lead_id' => '6923204000024550001' } } }])
    end

    it 'stays compatible with the legacy header_image_url field' do
      post_send_template(base_params.merge(header_image_url: 'https://dominio.com/fuego.png'))

      expect(response).to have_http_status(:ok)
      header = last_sent_components.find { |c| c['type'] == 'header' }
      expect(header['parameters']).to eq([{ 'type' => 'image', 'image' => { 'link' => 'https://dominio.com/fuego.png' } }])
    end

    it 'stays compatible with the legacy header_document_url/header_document_filename fields' do
      post_send_template(base_params.merge(
                           header_document_url: 'https://mdb3blnhtc41axtd.public.blob.vercel-storage.com/Brochure_FUEGO_julio14_2026.pdf',
                           header_document_filename: 'Brochure_FUEGO_julio14_2026.pdf',
                           body_params: ['Rodrigo'],
                           assignee_email: 'c.cruz@fuegocancun.com'
                         ))

      expect(response).to have_http_status(:ok)
      header = last_sent_components.find { |c| c['type'] == 'header' }
      expect(header['parameters']).to eq([{
                                           'type' => 'document',
                                           'document' => {
                                             'link' => 'https://mdb3blnhtc41axtd.public.blob.vercel-storage.com/Brochure_FUEGO_julio14_2026.pdf',
                                             'filename' => 'Brochure_FUEGO_julio14_2026.pdf'
                                           }
                                         }])
    end

    it 'rejects two header sources sent simultaneously with a 422 and explicit details' do
      post_send_template(base_params.merge(header_image_url: 'https://a.com/a.png', header_document_url: 'https://a.com/a.pdf'))

      expect(response).to have_http_status(:unprocessable_entity)
      body = response.parsed_body
      expect(body['error']).to eq('invalid_template_payload')
      expect(body['details']).to be_present
    end

    it 'rejects an unknown header type with a 422' do
      post_send_template(base_params.merge(header: { type: 'carousel' }))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('invalid_template_payload')
    end

    it 'preserves conversation assignment via assignee_email' do
      agent = create(:user, email: 'c.cruz@fuegocancun.com')
      create(:account_user, account: account, user: agent)

      post_send_template(base_params.merge(assignee_email: 'c.cruz@fuegocancun.com'))

      expect(response).to have_http_status(:ok)
      expect(inbox.conversations.last.assignee).to eq(agent)
    end

    context 'when Meta rejects the template (e.g. header format mismatch)' do
      before do
        stub_request(:post, /graph\.facebook\.com.*messages/).to_return(
          status: 400,
          body: {
            error: {
              message: '(#132012) Parameter format does not match format in the created template',
              type: 'OAuthException',
              code: 132_012,
              error_data: { details: 'header: Format mismatch, expected DOCUMENT, received UNKNOWN' },
              fbtrace_id: 'Abc123XyzTrace'
            }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
      end

      it 'propagates a diagnosable meta_error without leaking secrets' do
        post_send_template(base_params.merge(header_document_url: 'https://dominio.com/Brochure.pdf', header_document_filename: 'Brochure.pdf'))

        expect(response).to have_http_status(:unprocessable_entity)
        body = response.parsed_body
        expect(body['error']).to eq('template_send_failed')
        expect(body['meta_error']).to include('code' => 132_012, 'message' => a_string_including('132012'))
        expect(response.body).not_to include('test_key')
        expect(response.body).not_to include('Bearer')
      end
    end
  end
end
