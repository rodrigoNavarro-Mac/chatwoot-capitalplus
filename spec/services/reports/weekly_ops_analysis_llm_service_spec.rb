require 'rails_helper'

describe Reports::WeeklyOpsAnalysisLlmService do
  let(:account) { create(:account) }
  let(:kpis) { { inbox_name: 'Fuego', contact_time: { first_response: 10.0 } } }
  let(:mock_chat) { instance_double(RubyLLM::Chat) }
  let(:mock_response) { instance_double(RubyLLM::Message, content: response_content) }

  before do
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
    allow(mock_chat).to receive(:with_params).and_return(mock_chat)
    allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
    allow(mock_chat).to receive(:ask).and_return(mock_response)
  end

  describe '#generate' do
    context 'with a well-formed JSON response' do
      let(:response_content) do
        {
          executive_summary: 'Resumen ejecutivo de prueba.',
          contact_time: 'Se contesta rapido.',
          cadences: 'Las cadencias van bien.',
          some_unknown_key: 'esto no deberia colarse'
        }.to_json
      end

      it 'requests a JSON object response and splits executive_summary from the per-card analyses' do
        result = described_class.new(account: account, kpis: kpis).generate

        expect(mock_chat).to have_received(:with_params).with(response_format: { type: 'json_object' })
        expect(result[:executive_summary]).to eq('Resumen ejecutivo de prueba.')
        expect(result[:card_analyses]).to eq('contact_time' => 'Se contesta rapido.', 'cadences' => 'Las cadencias van bien.')
      end

      it 'drops any key from the response that is not a known card key' do
        result = described_class.new(account: account, kpis: kpis).generate

        expect(result[:card_analyses]).not_to have_key('some_unknown_key')
      end
    end

    context 'when the LLM wraps the JSON in a markdown code fence' do
      let(:response_content) { "```json\n{\"executive_summary\":\"Resumen.\",\"contact_time\":\"Nota.\"}\n```" }

      it 'strips the fence before parsing' do
        result = described_class.new(account: account, kpis: kpis).generate

        expect(result[:executive_summary]).to eq('Resumen.')
        expect(result[:card_analyses]).to eq('contact_time' => 'Nota.')
      end
    end

    context 'when the response is not valid JSON' do
      let(:response_content) { 'esto no es json' }

      it 'returns a blank result instead of raising' do
        result = described_class.new(account: account, kpis: kpis).generate

        expect(result).to eq(executive_summary: nil, card_analyses: {})
      end
    end

    context 'when RubyLLM raises' do
      let(:response_content) { nil }

      it 'reports the exception and returns a blank result' do
        allow(mock_chat).to receive(:ask).and_raise(RubyLLM::Error, 'boom')
        allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: nil))

        result = described_class.new(account: account, kpis: kpis).generate

        expect(result).to eq(executive_summary: nil, card_analyses: {})
        expect(ChatwootExceptionTracker).to have_received(:new)
      end
    end
  end
end
