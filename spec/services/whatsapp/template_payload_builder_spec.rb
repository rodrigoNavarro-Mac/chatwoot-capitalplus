require 'rails_helper'

describe Whatsapp::TemplatePayloadBuilder do
  describe '#call' do
    it 'returns an empty components array when there is no header, body or buttons' do
      expect(described_class.new.call).to eq([])
    end

    it 'converts legacy positional string body_params into a body component' do
      components = described_class.new(body_params: %w[Rodrigo Fuego]).call

      expect(components).to eq([{
                                 type: 'body',
                                 parameters: [{ type: 'text', text: 'Rodrigo' }, { type: 'text', text: 'Fuego' }]
                               }])
    end

    it 'builds a typed text body parameter' do
      components = described_class.new(body_params: [{ 'type' => 'text', 'text' => 'Rodrigo' }]).call

      expect(components.first[:parameters]).to eq([{ type: 'text', text: 'Rodrigo' }])
    end

    it 'builds a typed currency body parameter' do
      body_params = [{
        'type' => 'currency',
        'currency' => { 'fallback_value' => '$1,500,000 MXN', 'code' => 'MXN', 'amount_1000' => 1_500_000_000 }
      }]

      components = described_class.new(body_params: body_params).call

      expect(components.first[:parameters]).to eq([{
                                                    type: 'currency',
                                                    currency: { fallback_value: '$1,500,000 MXN', code: 'MXN', amount_1000: 1_500_000_000 }
                                                  }])
    end

    it 'raises when a currency body parameter is incomplete' do
      body_params = [{ 'type' => 'currency', 'currency' => { 'fallback_value' => '$1,500,000 MXN' } }]

      expect { described_class.new(body_params: body_params).call }.to raise_error(Whatsapp::TemplateValidationError)
    end

    it 'builds a typed date_time body parameter' do
      body_params = [{ 'type' => 'date_time', 'date_time' => { 'fallback_value' => '17 de julio de 2026' } }]

      components = described_class.new(body_params: body_params).call

      expect(components.first[:parameters].first[:date_time][:fallback_value]).to eq('17 de julio de 2026')
    end

    it 'raises when a date_time body parameter is missing fallback_value' do
      expect { described_class.new(body_params: [{ 'type' => 'date_time', 'date_time' => {} }]).call }
        .to raise_error(Whatsapp::TemplateValidationError)
    end

    it 'raises for an unknown body parameter type' do
      expect { described_class.new(body_params: [{ 'type' => 'carousel' }]).call }.to raise_error(Whatsapp::TemplateValidationError)
    end

    it 'does not add a body component when body_params is empty' do
      expect(described_class.new(body_params: []).call).to eq([])
    end

    it 'tags body parameters with parameter_name when named_parameter_keys is given' do
      components = described_class.new(body_params: %w[Rodrigo], named_parameter_keys: ['nombre']).call

      expect(components.first[:parameters]).to eq([{ type: 'text', parameter_name: 'nombre', text: 'Rodrigo' }])
    end

    it 'orders components as header, body, then buttons' do
      components = described_class.new(
        header: { 'type' => 'text', 'text' => 'Hola' },
        body_params: ['Rodrigo'],
        button_params: [{ 'type' => 'quick_reply', 'index' => 0, 'payload' => 'X' }]
      ).call

      expect(components.map { |c| c[:type] }).to eq(%w[header body button])
    end

    it 'builds the exact payload documented for wa_segundo_intento (document header)' do
      components = described_class.new(
        header: { 'type' => 'document', 'link' => 'https://mdb3blnhtc41axtd.public.blob.vercel-storage.com/Brochure_FUEGO_julio14_2026.pdf',
                  'filename' => 'Brochure_FUEGO_julio14_2026.pdf' },
        body_params: ['Rodrigo']
      ).call

      expect(components).to eq([
                                 {
                                   type: 'header',
                                   parameters: [{
                                     type: 'document',
                                     document: {
                                       link: 'https://mdb3blnhtc41axtd.public.blob.vercel-storage.com/Brochure_FUEGO_julio14_2026.pdf',
                                       filename: 'Brochure_FUEGO_julio14_2026.pdf'
                                     }
                                   }]
                                 },
                                 { type: 'body', parameters: [{ type: 'text', text: 'Rodrigo' }] }
                               ])
    end
  end
end
