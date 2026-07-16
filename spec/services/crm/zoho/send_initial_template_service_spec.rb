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

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
    stub_request(:post, /graph\.facebook\.com.*messages/)
      .to_return(status: 200, body: { messages: [{ id: 'wamid.zoho1' }] }.to_json, headers: { 'Content-Type' => 'application/json' })
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

    it 'raises when the assignee email does not match an existing agent' do
      params_with_bad_assignee = params.merge(assignee_email: 'no-such-agent@example.com')

      expect { described_class.new(account, params_with_bad_assignee).perform }.not_to raise_error
      expect(inbox.conversations.last.assignee).to be_nil
    end

    it 'raises template_not_found_or_not_approved for an unknown template' do
      bad_params = params.merge(template_name: 'does_not_exist')

      expect { described_class.new(account, bad_params).perform }.to raise_error('template_not_found_or_not_approved')
    end
  end
end
