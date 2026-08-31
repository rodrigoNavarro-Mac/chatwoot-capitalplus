require 'rails_helper'

describe Crm::Aircall::WhisperTranscriptFallbackService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:call) do
    create(:call, account: account, conversation: conversation, provider: :aircall, status: 'completed', duration_seconds: 42)
  end

  before { allow(Llm::SpeechToTextService).to receive(:available_for?).and_return(true) }

  def attach_recording!
    call.recording.attach(io: StringIO.new('AUDIO'), filename: 'call.wav', content_type: 'audio/wav')
  end

  it 'wraps the plain Whisper transcript in a single undiarized segment' do
    attach_recording!
    allow(Llm::SpeechToTextService).to receive(:too_large?).and_return(false)
    allow(Llm::SpeechToTextService).to receive(:new).and_return(instance_double(Llm::SpeechToTextService, perform: 'Hola, buenas tardes'))

    result = described_class.new(call: call).perform

    expect(result).to be true
    call.reload
    expect(call.transcript).to eq('Hola, buenas tardes')
    expect(call.transcript_source).to eq('whisper_fallback')
    expect(call.transcript_segments).to eq([
                                             { 'speaker' => 'Transcripción', 'role_hint' => nil, 'start_seconds' => 0,
                                               'end_seconds' => 42, 'text' => 'Hola, buenas tardes' }
                                           ])
  end

  it 'is a no-op when segments are already present' do
    call.update!(transcript_segments: [{ 'speaker' => 'x', 'text' => 'y', 'start_seconds' => 0 }])

    expect(Llm::SpeechToTextService).not_to receive(:new)

    expect(described_class.new(call: call).perform).to be true
  end

  it 'returns false when there is no recording attached' do
    expect(described_class.new(call: call).perform).to be false
  end

  it 'returns false when transcription is unavailable for the account' do
    attach_recording!
    allow(Llm::SpeechToTextService).to receive(:available_for?).and_return(false)

    expect(described_class.new(call: call).perform).to be false
  end

  it 'returns false when the recording exceeds the size limit' do
    attach_recording!
    allow(Llm::SpeechToTextService).to receive(:too_large?).and_return(true)

    expect(Llm::SpeechToTextService).not_to receive(:new)
    expect(described_class.new(call: call).perform).to be false
  end
end
