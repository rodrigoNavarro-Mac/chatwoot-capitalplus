require 'rails_helper'

RSpec.describe AgentBots::InternalFlowHandlerService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { whatsapp_channel.inbox }

  let(:bot_config) do
    {
      'variables' => {
        'desarrollo_nombre' => 'Torre Diamante',
        'precio_desde' => '$3,000,000'
      },
      'initial_step' => 'welcome',
      'steps' => {
        'welcome' => {
          'message' => 'Hola! Bienvenido a {{desarrollo_nombre}}. Precios desde {{precio_desde}}. ¿Qué buscas? 1. Comprar 2. Rentar',
          'transitions' => [
            { 'when' => { 'contains' => ['1', 'comprar'] }, 'next_step' => 'compra' },
            { 'when' => { 'contains' => ['2', 'rentar'] }, 'next_step' => 'renta' },
            { 'when' => { 'default' => true }, 'next_step' => 'no_entendido' }
          ]
        },
        'compra' => {
          'message' => 'Excelente! Tenemos propiedades en venta en {{desarrollo_nombre}}. ¿Agendamos una cita? 1. Sí 2. Llamada',
          'transitions' => [
            { 'when' => { 'contains' => ['1', 'si', 'sí'] }, 'next_step' => 'cita' },
            { 'when' => { 'contains' => ['2', 'llamada'] }, 'next_step' => 'llamada' },
            { 'when' => { 'default' => true }, 'next_step' => 'compra' }
          ]
        },
        'renta' => {
          'message' => 'Tenemos rentas disponibles. ¿Te llamo ahora?',
          'transitions' => [
            { 'when' => { 'default' => true }, 'next_step' => 'llamada' }
          ]
        },
        'no_entendido' => {
          'message' => 'No te entendí. Escribe 1 para comprar o 2 para rentar.',
          'transitions' => [
            { 'when' => { 'default' => true }, 'next_step' => 'welcome' }
          ]
        },
        'cita' => {
          'message' => 'Perfecto! Un asesor te contactará para confirmar la cita.',
          'transitions' => [
            { 'when' => { 'default' => true }, 'next_step' => 'cita' }
          ]
        },
        'llamada' => {
          'message' => 'Te transfiero con un asesor ahora.',
          'action' => 'open_conversation'
        }
      }
    }
  end

  let(:agent_bot) do
    create(:agent_bot, account: account, bot_type: :internal_flow, outgoing_url: nil,
                       bot_config: bot_config)
  end

  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(:conversation, contact: contact, inbox: inbox, account: account,
                          contact_inbox: contact_inbox)
  end

  describe '#perform' do
    context 'cuando la conversación empieza sin paso guardado (primer mensaje)' do
      it 'envía el mensaje del initial_step sin importar el contenido' do
        described_class.new(agent_bot, conversation, 'hola').perform

        last_message = conversation.messages.outgoing.last
        expect(last_message).not_to be_nil
        expect(last_message.content).to include('Bienvenido')
      end

      it 'guarda el initial_step en custom_attributes' do
        described_class.new(agent_bot, conversation, 'hola').perform

        expect(conversation.reload.custom_attributes['_bot_current_step']).to eq('welcome')
      end

      it 'muestra el welcome incluso si el mensaje parece una opción' do
        described_class.new(agent_bot, conversation, '1').perform

        expect(conversation.reload.custom_attributes['_bot_current_step']).to eq('welcome')
      end
    end

    context 'cuando el mensaje coincide con una transición contains' do
      before { conversation.update!(custom_attributes: { '_bot_current_step' => 'welcome' }) }

      it 'navega al paso correcto al escribir "comprar"' do
        described_class.new(agent_bot, conversation, 'quiero comprar').perform

        expect(conversation.reload.custom_attributes['_bot_current_step']).to eq('compra')
      end

      it 'navega al paso correcto al escribir "1"' do
        described_class.new(agent_bot, conversation, '1').perform

        expect(conversation.reload.custom_attributes['_bot_current_step']).to eq('compra')
      end

      it 'navega al paso correcto al escribir "2"' do
        described_class.new(agent_bot, conversation, '2').perform

        expect(conversation.reload.custom_attributes['_bot_current_step']).to eq('renta')
      end
    end

    context 'cuando el mensaje no coincide con ninguna transición (fallback default)' do
      before { conversation.update!(custom_attributes: { '_bot_current_step' => 'welcome' }) }

      it 'usa la transición default' do
        described_class.new(agent_bot, conversation, 'mensaje incomprensible xyz').perform

        expect(conversation.reload.custom_attributes['_bot_current_step']).to eq('no_entendido')
      end
    end

    context 'cuando el paso tiene action: open_conversation' do
      before do
        conversation.update!(custom_attributes: { '_bot_current_step' => 'compra' })
      end

      it 'cambia el estado de la conversación a open al elegir "llamada"' do
        conversation.update!(status: :pending)

        described_class.new(agent_bot, conversation, '2').perform

        expect(conversation.reload.status).to eq('open')
      end
    end

    context 'interpolación de variables' do
      it 'reemplaza {{variable}} en el mensaje del welcome' do
        described_class.new(agent_bot, conversation, 'hola').perform

        last_message = conversation.messages.outgoing.last
        expect(last_message.content).to include('Torre Diamante')
        expect(last_message.content).to include('$3,000,000')
        expect(last_message.content).not_to include('{{desarrollo_nombre}}')
        expect(last_message.content).not_to include('{{precio_desde}}')
      end

      it 'reemplaza {{variable}} en pasos posteriores' do
        conversation.update!(custom_attributes: { '_bot_current_step' => 'welcome' })
        described_class.new(agent_bot, conversation, '1').perform

        last_message = conversation.messages.outgoing.last
        expect(last_message.content).to include('Torre Diamante')
      end
    end

    context 'cuando el inbox no es WhatsApp' do
      let(:api_channel) { create(:channel_api, account: account) }
      let(:api_inbox) { create(:inbox, channel: api_channel, account: account) }
      let(:api_conversation) { create(:conversation, inbox: api_inbox, account: account) }

      it 'no hace nada' do
        expect(Messages::MessageBuilder).not_to receive(:new)

        described_class.new(agent_bot, api_conversation, '1').perform
      end
    end

    context 'cuando bot_config no tiene initial_step' do
      let(:agent_bot) do
        create(:agent_bot, account: account, bot_type: :internal_flow, outgoing_url: nil,
                           bot_config: {})
      end

      it 'no hace nada' do
        expect(Messages::MessageBuilder).not_to receive(:new)

        described_class.new(agent_bot, conversation, '1').perform
      end
    end

    context 'comparación case-insensitive' do
      it 'coincide independientemente de mayúsculas' do
        described_class.new(agent_bot, conversation, 'COMPRAR').perform

        expect(conversation.reload.custom_attributes['_bot_current_step']).to eq('compra')
      end
    end

    context 'el paso guardado avanza correctamente' do
      before do
        conversation.update!(custom_attributes: { '_bot_current_step' => 'compra' })
      end

      it 'procesa desde el paso actual, no desde el inicial' do
        described_class.new(agent_bot, conversation, 'sí').perform

        expect(conversation.reload.custom_attributes['_bot_current_step']).to eq('cita')
      end
    end
  end
end
