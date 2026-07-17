require 'rails_helper'

describe Crm::Zoho::SendInitialTemplateService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { whatsapp_channel.inbox }
  let!(:agent_bot) { create(:agent_bot, account: account, bot_config: { 'variables' => { 'desarrollo' => 'torre-1' } }) }
  let(:params) do
    {
      phone: '5215551234567',
      contact_name: 'Juan Perez',
      desarrollo: 'torre-1',
      template_name: 'test_no_params_template',
      template_language: 'en',
      body_params: []
    }
  end

  let(:sent_requests) { [] }
  let(:sent_request_body) { sent_requests.last&.body }

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
    stub_request(:post, /graph\.facebook\.com.*messages/).to_return do |request|
      sent_requests << request
      { status: 200, body: { messages: [{ id: 'wamid.zoho1' }] }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  describe '#perform' do
    it 'sends the approved template and creates the outgoing message' do
      described_class.new(account, params).perform

      conversation = inbox.conversations.last
      message = conversation.messages.last

      expect(message.message_type).to eq('outgoing')
      expect(message.source_id).to eq('wamid.zoho1')
      expect(message.content).to include('Thank you for contacting us')
    end

    it 'stamps additional_attributes.template_params on the message, the same marker the composer/API leave' do
      described_class.new(account, params).perform

      message = inbox.conversations.last.messages.last

      expect(message.additional_attributes['template_params']).to include(
        'name' => 'test_no_params_template',
        'language' => 'en'
      )
    end

    it 'does not raise when the assignee email does not match an existing agent' do
      params_with_bad_assignee = params.merge(assignee_email: 'no-such-agent@example.com')

      expect { described_class.new(account, params_with_bad_assignee).perform }.not_to raise_error
      expect(inbox.conversations.last.assignee).to be_nil
    end

    it 'assigns the conversation to the agent matching assignee_email' do
      agent = create(:user, email: 'c.cruz@fuegocancun.com')
      create(:account_user, account: account, user: agent)

      described_class.new(account, params.merge(assignee_email: 'C.Cruz@fuegocancun.com')).perform

      expect(inbox.conversations.last.assignee).to eq(agent)
    end

    it 'raises template_not_found_or_not_approved for an unknown template' do
      bad_params = params.merge(template_name: 'does_not_exist')

      expect { described_class.new(account, bad_params).perform }.to raise_error('template_not_found_or_not_approved')
    end

    it 'raises template_language_required when template_language is blank' do
      bad_params = params.merge(template_language: '')

      expect { described_class.new(account, bad_params).perform }.to raise_error('template_language_required')
    end

    context 'with a legacy header_image_url payload' do
      it 'sends an image header component to Meta' do
        described_class.new(account, params.merge(header_image_url: 'https://dominio.com/fuego.png')).perform

        sent_components = JSON.parse(sent_request_body)['template']['components']
        header = sent_components.find { |c| c['type'] == 'header' }

        expect(header['parameters']).to eq([{ 'type' => 'image', 'image' => { 'link' => 'https://dominio.com/fuego.png' } }])
      end
    end

    context 'with a legacy header_document_url + header_document_filename payload' do
      it 'sends a document header component with type DOCUMENT to Meta' do
        described_class.new(account, params.merge(
                                       header_document_url: 'https://mdb3blnhtc41axtd.public.blob.vercel-storage.com/Brochure_FUEGO_julio14_2026.pdf',
                                       header_document_filename: 'Brochure_FUEGO_julio14_2026.pdf'
                                     )).perform

        sent_components = JSON.parse(sent_request_body)['template']['components']
        header = sent_components.find { |c| c['type'] == 'header' }

        expect(header['parameters']).to eq([{
                                             'type' => 'document',
                                             'document' => {
                                               'link' => 'https://mdb3blnhtc41axtd.public.blob.vercel-storage.com/Brochure_FUEGO_julio14_2026.pdf',
                                               'filename' => 'Brochure_FUEGO_julio14_2026.pdf'
                                             }
                                           }])
      end
    end

    context 'with the new normalized header object' do
      it 'sends the corresponding header type to Meta' do
        described_class.new(account, params.merge(header: { type: 'image', link: 'https://dominio.com/imagen.png' })).perform

        sent_components = JSON.parse(sent_request_body)['template']['components']
        header = sent_components.find { |c| c['type'] == 'header' }

        expect(header['parameters']).to eq([{ 'type' => 'image', 'image' => { 'link' => 'https://dominio.com/imagen.png' } }])
      end
    end

    it 'raises Whatsapp::TemplateValidationError when two header sources are sent simultaneously' do
      bad_params = params.merge(header_image_url: 'https://a.com/a.png', header_document_url: 'https://a.com/a.pdf')

      expect { described_class.new(account, bad_params).perform }.to raise_error(Whatsapp::TemplateValidationError)
    end

    it 'raises Whatsapp::TemplateValidationError for an unknown header type' do
      bad_params = params.merge(header: { type: 'carousel' })

      expect { described_class.new(account, bad_params).perform }.to raise_error(Whatsapp::TemplateValidationError)
    end

    context 'with dynamic buttons' do
      it 'sends a quick_reply button component to Meta' do
        described_class.new(account, params.merge(button_params: [{ type: 'quick_reply', index: 0, payload: 'CONFIRMAR_VISITA' }])).perform

        sent_components = JSON.parse(sent_request_body)['template']['components']
        button = sent_components.find { |c| c['type'] == 'button' }

        expect(button).to include('sub_type' => 'quick_reply', 'index' => '0')
        expect(button['parameters']).to eq([{ 'type' => 'payload', 'payload' => 'CONFIRMAR_VISITA' }])
      end

      it 'sends a flow button component to Meta' do
        button_params = [{ type: 'flow', index: 0, flow_token: 'TOKEN_DEL_FLUJO', flow_action_data: { lead_id: '6923204000024550001' } }]

        described_class.new(account, params.merge(button_params: button_params)).perform

        sent_components = JSON.parse(sent_request_body)['template']['components']
        button = sent_components.find { |c| c['type'] == 'button' }

        expect(button['parameters']).to eq([{ 'type' => 'action',
                                              'action' => { 'flow_token' => 'TOKEN_DEL_FLUJO',
                                                            'flow_action_data' => { 'lead_id' => '6923204000024550001' } } }])
      end
    end

    context 'when the template uses NAMED parameters' do
      let(:named_params) do
        {
          phone: '5215551234567',
          desarrollo: 'torre-1',
          template_name: 'ticket_status_updated',
          template_language: 'en',
          body_params: %w[John 2332]
        }
      end

      it 'still tags the body parameters with parameter_name and renders readable content' do
        described_class.new(account, named_params).perform

        message = inbox.conversations.last.messages.last
        sent_components = JSON.parse(sent_request_body)['template']['components']
        body = sent_components.find { |c| c['type'] == 'body' }

        expect(body['parameters']).to eq([
                                           { 'type' => 'text', 'parameter_name' => 'name', 'text' => 'John' },
                                           { 'type' => 'text', 'parameter_name' => 'ticket_id', 'text' => '2332' }
                                         ])
        expect(message.content).to eq('Hello John,  Your support ticket with ID: #2332 has been updated by the support agent.')
      end
    end

    context 'when Meta rejects the template send' do
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

      it 'raises Crm::Zoho::TemplateSendError carrying Meta error details and no secrets' do
        expect { described_class.new(account, params).perform }.to raise_error do |error|
          expect(error).to be_a(Crm::Zoho::TemplateSendError)
          expect(error.http_status).to eq(:unprocessable_entity)
          expect(error.meta_error).to eq(
            message: '(#132012) Parameter format does not match format in the created template',
            code: 132_012,
            type: 'OAuthException',
            details: 'header: Format mismatch, expected DOCUMENT, received UNKNOWN',
            fbtrace_id: 'Abc123XyzTrace'
          )
          expect(error.meta_error.values.join).not_to include('test_key')
        end
      end

      it 'does not create a conversation message when the send fails' do
        expect { described_class.new(account, params).perform }.to raise_error(Crm::Zoho::TemplateSendError)
        expect(inbox.conversations.count).to eq(0)
      end
    end
  end
end
