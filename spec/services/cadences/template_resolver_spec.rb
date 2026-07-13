require 'rails_helper'

describe Cadences::TemplateResolver do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, assignee: agent, status: 'open')
  end

  describe '#resolve' do
    it 'falls back to the default YAML mapping when the inbox has no override' do
      result = described_class.new(template_key: 'wa_primer_contacto', conversation: conversation).resolve

      expect(result['name']).to eq('cadencia_primer_contacto')
      expect(result['language']).to eq('es_MX')
    end

    it 'prefers a database override configured for the inbox over the default mapping' do
      CadenceTemplateMapping.create!(
        account: account,
        inbox: whatsapp_inbox,
        template_key: 'wa_primer_contacto',
        name: 'cadencia_primer_contacto_torre_sur',
        language: 'es_MX'
      )

      result = described_class.new(template_key: 'wa_primer_contacto', conversation: conversation).resolve

      expect(result['name']).to eq('cadencia_primer_contacto_torre_sur')
    end

    it 'does not let an override on a different inbox leak into this one' do
      other_channel = create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false)
      CadenceTemplateMapping.create!(
        account: account,
        inbox: other_channel.inbox,
        template_key: 'wa_primer_contacto',
        name: 'plantilla_de_otro_inbox',
        language: 'es_MX'
      )

      result = described_class.new(template_key: 'wa_primer_contacto', conversation: conversation).resolve

      expect(result['name']).to eq('cadencia_primer_contacto')
    end
  end
end
