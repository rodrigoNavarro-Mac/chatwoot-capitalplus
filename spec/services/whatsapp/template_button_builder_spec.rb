require 'rails_helper'

describe Whatsapp::TemplateButtonBuilder do
  subject(:builder) { described_class.new }

  describe '#call' do
    it 'returns an empty array for blank input' do
      expect(builder.call(nil)).to eq([])
      expect(builder.call([])).to eq([])
    end

    it 'builds a quick_reply button' do
      result = builder.call([{ 'type' => 'quick_reply', 'index' => 0, 'payload' => 'CONFIRMAR_VISITA' }])

      expect(result).to eq([{
                             type: 'button', sub_type: 'quick_reply', index: '0',
                             parameters: [{ type: 'payload', payload: 'CONFIRMAR_VISITA' }]
                           }])
    end

    it 'builds a dynamic url button' do
      result = builder.call([{ 'type' => 'url', 'index' => 1, 'text' => 'lead-123' }])

      expect(result).to eq([{
                             type: 'button', sub_type: 'url', index: '1',
                             parameters: [{ type: 'text', text: 'lead-123' }]
                           }])
    end

    it 'builds a flow button' do
      result = builder.call([{
                              'type' => 'flow', 'index' => 0, 'flow_token' => 'TOKEN_DEL_FLUJO',
                              'flow_action_data' => { 'lead_id' => '6923204000024550001' }
                            }])

      expect(result).to eq([{
                             type: 'button', sub_type: 'flow', index: '0',
                             parameters: [{ type: 'action', action: { flow_token: 'TOKEN_DEL_FLUJO', flow_action_data: { 'lead_id' => '6923204000024550001' } } }]
                           }])
    end

    it 'orders the resulting components by index' do
      result = builder.call([
                              { 'type' => 'quick_reply', 'index' => 1, 'payload' => 'B' },
                              { 'type' => 'quick_reply', 'index' => 0, 'payload' => 'A' }
                            ])

      expect(result.map { |c| c[:index] }).to eq(%w[0 1])
    end

    it 'raises when index is missing' do
      expect { builder.call([{ 'type' => 'quick_reply', 'payload' => 'A' }]) }.to raise_error(Whatsapp::TemplateValidationError)
    end

    it 'raises for an unknown button subtype' do
      expect { builder.call([{ 'type' => 'carousel', 'index' => 0 }]) }.to raise_error(Whatsapp::TemplateValidationError)
    end

    it 'raises when a flow button is missing flow_token' do
      expect { builder.call([{ 'type' => 'flow', 'index' => 0 }]) }.to raise_error(Whatsapp::TemplateValidationError)
    end
  end
end
