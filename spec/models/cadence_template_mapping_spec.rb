require 'rails_helper'

describe CadenceTemplateMapping do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }

  it 'is valid with a fixed template_key, a name and a language' do
    mapping = described_class.new(
      account: account,
      inbox: whatsapp_inbox,
      template_key: 'wa_primer_contacto',
      name: 'cadencia_primer_contacto_torre_sur',
      language: 'es_MX'
    )

    expect(mapping).to be_valid
  end

  it 'rejects a template_key outside the fixed cadence steps' do
    mapping = described_class.new(
      account: account,
      inbox: whatsapp_inbox,
      template_key: 'not_a_real_step',
      name: 'whatever',
      language: 'es_MX'
    )

    expect(mapping).not_to be_valid
    expect(mapping.errors[:template_key]).to be_present
  end

  it 'does not allow two mappings for the same template_key on the same inbox' do
    described_class.create!(account: account, inbox: whatsapp_inbox, template_key: 'wa_primer_contacto', name: 'a', language: 'es_MX')
    duplicate = described_class.new(account: account, inbox: whatsapp_inbox, template_key: 'wa_primer_contacto', name: 'b', language: 'es_MX')

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:template_key]).to be_present
  end
end
