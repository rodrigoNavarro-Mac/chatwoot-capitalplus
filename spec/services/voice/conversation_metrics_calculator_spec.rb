require 'rails_helper'

describe Voice::ConversationMetricsCalculator do
  subject(:result) { described_class.new(segments: segments, agent_speaker_labels: ['Agent']).calculate }

  let(:segments) do
    [
      { 'speaker' => 'Agent', 'start_seconds' => 0, 'text' => 'Hola buenas tardes' },
      { 'speaker' => 'Contact', 'start_seconds' => 5, 'text' => 'Hola' },
      { 'speaker' => 'Agent', 'start_seconds' => 8, 'text' => '¿Cómo estás? ¿Verdad que sí?' },
      { 'speaker' => 'Contact', 'start_seconds' => 15, 'text' => 'Bien gracias' },
      { 'speaker' => 'Agent', 'start_seconds' => 18, 'text' => 'Perfecto, te comparto la información por WhatsApp' }
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

  context 'without segments' do
    subject(:result) { described_class.new(segments: [], agent_speaker_labels: ['Agent']).calculate }

    it 'returns a safe empty result instead of raising' do
      expect(result).to eq(talk_ratio: nil, longest_monologue_seconds: 0, questions: { open: 0, closed: 0 }, cta_used: false,
                           total_duration_seconds: 0)
    end
  end
end
