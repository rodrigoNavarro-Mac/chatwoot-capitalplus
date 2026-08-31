require 'rails_helper'

describe Voice::ConversationMetricsCalculator do
  subject(:result) { described_class.new(segments: segments).calculate }

  let(:segments) do
    [
      { 'speaker' => 'Agente', 'role_hint' => 'agent', 'start_seconds' => 0, 'text' => 'Hola buenas tardes' },
      { 'speaker' => 'Cliente', 'role_hint' => 'external', 'start_seconds' => 5, 'text' => 'Hola' },
      { 'speaker' => 'Agente', 'role_hint' => 'agent', 'start_seconds' => 8, 'text' => '¿Cómo estás? ¿Verdad que sí?' },
      { 'speaker' => 'Cliente', 'role_hint' => 'external', 'start_seconds' => 15, 'text' => 'Bien gracias' },
      { 'speaker' => 'Agente', 'role_hint' => 'agent', 'start_seconds' => 18, 'text' => 'Perfecto, te comparto la información por WhatsApp' }
    ]
  end

  it 'computes talk ratio as agent seconds over total duration' do
    expect(result[:total_duration_seconds]).to eq(18)
    expect(result[:talk_ratio]).to eq(0.67)
  end

  it 'computes the longest single-speaker run' do
    expect(result[:longest_monologue_seconds]).to eq(7)
  end

  it 'classifies open vs closed questions by the first interrogative word' do
    expect(result[:questions]).to eq({ open: 1, closed: 1 })
  end

  it 'detects a CTA keyword in the agent speech' do
    expect(result[:cta_used]).to be true
  end

  context 'without role_hint (undiarized Whisper fallback transcript)' do
    let(:segments) do
      [{ 'speaker' => 'Transcripción', 'role_hint' => nil, 'start_seconds' => 0, 'end_seconds' => 20,
         'text' => '¿Cómo estás? Perfecto, te comparto la info' }]
    end

    it 'degrades talk_ratio to nil instead of a misleading number' do
      expect(result[:talk_ratio]).to be_nil
    end

    it 'still counts questions and CTA from the full text' do
      expect(result[:questions]).to eq({ open: 1, closed: 0 })
      expect(result[:cta_used]).to be true
    end
  end

  context 'without segments' do
    subject(:result) { described_class.new(segments: []).calculate }

    it 'returns a safe empty result instead of raising' do
      expect(result).to eq(talk_ratio: nil, longest_monologue_seconds: 0, questions: { open: 0, closed: 0 }, cta_used: false,
                           total_duration_seconds: 0)
    end
  end
end
