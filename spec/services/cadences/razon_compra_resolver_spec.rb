require 'rails_helper'

describe Cadences::RazonCompraResolver do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, status: 'open')
  end

  describe '#resolve' do
    it 'uses the value captured locally by the bot when the contact has no Zoho link' do
      conversation.update!(custom_attributes: { 'razon_compra' => 'Inversión' })

      expect(described_class.new(conversation: conversation).resolve).to eq('Inversión')
    end

    it 'returns nil when there is no local value and no Zoho link' do
      expect(described_class.new(conversation: conversation).resolve).to be_nil
    end

    # rubocop:disable RSpec/AnyInstance -- Cadences::RazonCompraResolver instancia
    # Crm::Zoho::ContactFinderService internamente; no hay forma de inyectar un doble sin
    # agregarle un parámetro solo para testing.
    context 'when the contact is linked to a Zoho record' do
      before do
        contact.update!(additional_attributes: { 'external' => { 'zoho_id' => 'zoho-123', 'zoho_module' => 'Leads' } })
        account.enable_features!('crm_integration')
        create(
          :integrations_hook, account: account, app_id: 'zoho_crm', status: 'enabled',
                               settings: { client_id: 'x', client_secret: 'y', refresh_token: 'z' }
        )
        conversation.update!(custom_attributes: { 'razon_compra' => 'Inversión' })
      end

      it 'prefers the live value from Zoho over the locally captured one' do
        allow_any_instance_of(Crm::Zoho::ContactFinderService).to receive(:fetch_record).and_return({ 'Raz_n_de_compra' => 'Vivienda' })

        expect(described_class.new(conversation: conversation).resolve).to eq('Vivienda')
      end

      it 'falls back to the local value if the Zoho lookup fails' do
        allow_any_instance_of(Crm::Zoho::ContactFinderService).to receive(:fetch_record).and_raise(StandardError, 'boom')

        expect(described_class.new(conversation: conversation).resolve).to eq('Inversión')
      end

      it 'falls back to the local value if Zoho has no value for that field' do
        allow_any_instance_of(Crm::Zoho::ContactFinderService).to receive(:fetch_record).and_return({})

        expect(described_class.new(conversation: conversation).resolve).to eq('Inversión')
      end
    end
    # rubocop:enable RSpec/AnyInstance
  end
end
