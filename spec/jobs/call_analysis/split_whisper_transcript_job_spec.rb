require 'rails_helper'

RSpec.describe CallAnalysis::SplitWhisperTranscriptJob, type: :job do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:call) do
    create(:call, account: account, conversation: conversation, provider: :aircall, status: 'completed',
                  transcript: 'Hola', transcript_source: 'whisper_fallback')
  end

  it 'does nothing when the call no longer exists' do
    expect(CallAnalysis::TranscriptSpeakerSplitService).not_to receive(:new)

    expect { described_class.perform_now(call.id + 1) }.not_to raise_error
  end

  it "does nothing when the call's transcript_source is not whisper_fallback (already split, or diarized)" do
    call.update!(transcript_source: 'whisper_fallback_llm_split')

    expect(CallAnalysis::TranscriptSpeakerSplitService).not_to receive(:new)

    described_class.perform_now(call.id)
  end

  it 'runs the speaker split for a call still on the flat whisper_fallback transcript' do
    split_double = instance_double(CallAnalysis::TranscriptSpeakerSplitService, perform: true)
    expect(CallAnalysis::TranscriptSpeakerSplitService).to receive(:new).with(call: call).and_return(split_double)

    described_class.perform_now(call.id)
  end
end
