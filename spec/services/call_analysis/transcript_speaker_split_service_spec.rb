require 'rails_helper'

describe CallAnalysis::TranscriptSpeakerSplitService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:call) do
    create(:call, account: account, conversation: conversation, provider: :aircall, status: 'completed',
                  transcript: 'Hola, le llamo del desarrollo Fuego. Hola, ¿qué tal?')
  end
  let(:mock_chat) { instance_double(RubyLLM::Chat) }
  let(:mock_response) { instance_double(RubyLLM::Message, content: response_content) }

  before do
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
    allow(mock_chat).to receive(:with_params).and_return(mock_chat)
    allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
    allow(mock_chat).to receive(:ask).and_return(mock_response)
  end

  describe '#perform' do
    context 'with a well-formed turns response' do
      let(:response_content) do
        {
          turns: [
            { speaker: 'agent', text: 'Hola, le llamo del desarrollo Fuego.' },
            { speaker: 'contact', text: 'Hola, ¿qué tal?' }
          ]
        }.to_json
      end

      it 'saves ordered segments with speaker labels but without role_hint (avoids feeding fake timing into metrics)' do
        result = described_class.new(call: call).perform

        expect(result).to be true
        call.reload
        expect(call.transcript_source).to eq('whisper_fallback_llm_split')
        expect(call.transcript_segments).to eq([
                                                 { 'speaker' => 'Agente', 'role_hint' => nil, 'start_seconds' => 0,
                                                   'end_seconds' => 1, 'text' => 'Hola, le llamo del desarrollo Fuego.' },
                                                 { 'speaker' => 'Cliente', 'role_hint' => nil, 'start_seconds' => 1,
                                                   'end_seconds' => 2, 'text' => 'Hola, ¿qué tal?' }
                                               ])
      end
    end

    context 'when the LLM includes a turn with an invalid speaker value' do
      let(:response_content) { { turns: [{ speaker: 'narrator', text: 'x' }, { speaker: 'agent', text: 'Hola' }] }.to_json }

      it 'drops the invalid turn but keeps the valid ones' do
        described_class.new(call: call).perform

        expect(call.reload.transcript_segments.size).to eq(1)
      end
    end

    context 'when the response has no usable turns' do
      let(:response_content) { { turns: [] }.to_json }

      it 'returns false and leaves the call untouched' do
        result = described_class.new(call: call).perform

        expect(result).to be false
        expect(call.reload.transcript_segments).to be_blank
      end
    end

    context 'when the response is not valid JSON' do
      let(:response_content) { 'esto no es json' }

      it 'returns false instead of raising' do
        expect(described_class.new(call: call).perform).to be false
      end
    end

    context 'when RubyLLM raises' do
      let(:response_content) { nil }

      it 'reports the exception and returns false' do
        allow(mock_chat).to receive(:ask).and_raise(RubyLLM::Error, 'boom')
        allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: nil))

        expect(described_class.new(call: call).perform).to be false
        expect(ChatwootExceptionTracker).to have_received(:new)
      end
    end

    context 'when the call has no transcript yet' do
      let(:response_content) { nil }

      it 'returns false without calling the LLM' do
        call.update!(transcript: nil)

        expect(RubyLLM).not_to receive(:chat)
        expect(described_class.new(call: call).perform).to be false
      end
    end
  end
end
