require 'rails_helper'

describe Cadences::CadenceDefinitionResolver do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, status: 'open')
  end

  def build_definition(segment_value: nil, is_default: false)
    CadenceDefinition.create!(
      account: account, inbox: whatsapp_inbox, name: "cadence #{SecureRandom.hex(2)}",
      segment_value: segment_value, is_default: is_default
    )
  end

  describe '#resolve' do
    it 'returns the definition matching the segment when there is exactly one' do
      matching = build_definition(segment_value: 'Inversión')
      build_definition(segment_value: 'Vivienda')
      conversation.update!(custom_attributes: { 'razon_compra' => 'Inversión' })

      expect(described_class.new(conversation: conversation).resolve).to eq(matching)
    end

    it 'balances leads between variants of the same segment by least enrollment count' do
      variant_a = build_definition(segment_value: 'Inversión')
      variant_b = build_definition(segment_value: 'Inversión')
      conversation.update!(custom_attributes: { 'razon_compra' => 'Inversión' })

      other_contact = create(:contact, account: account, phone_number: '+15557654321')
      other_conversation = create(:conversation, account: account, inbox: whatsapp_inbox, contact: other_contact, status: 'open')
      CadenceEnrollment.create!(
        account: account, conversation: other_conversation, contact: other_contact, inbox: whatsapp_inbox,
        cadence_definition: variant_a
      )

      expect(described_class.new(conversation: conversation).resolve).to eq(variant_b)
    end

    it 'falls back to the default definition when no segment matches' do
      default_definition = build_definition(is_default: true)
      build_definition(segment_value: 'Vivienda')
      conversation.update!(custom_attributes: { 'razon_compra' => 'Inversión' })

      expect(described_class.new(conversation: conversation).resolve).to eq(default_definition)
    end

    it 'falls back to the default definition when razon_compra is blank' do
      default_definition = build_definition(is_default: true)

      expect(described_class.new(conversation: conversation).resolve).to eq(default_definition)
    end

    it 'returns nil when nothing matches and there is no default' do
      build_definition(segment_value: 'Vivienda')

      expect(described_class.new(conversation: conversation).resolve).to be_nil
    end

    it 'ignores inactive definitions' do
      build_definition(segment_value: 'Inversión').update!(active: false)
      conversation.update!(custom_attributes: { 'razon_compra' => 'Inversión' })

      expect(described_class.new(conversation: conversation).resolve).to be_nil
    end
  end
end
