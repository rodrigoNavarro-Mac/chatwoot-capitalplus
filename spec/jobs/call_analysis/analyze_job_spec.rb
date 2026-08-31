require 'rails_helper'

RSpec.describe CallAnalysis::AnalyzeJob, type: :job do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:call) do
    create(:call, account: account, conversation: conversation, provider: :aircall, accepted_by_agent: agent, status: 'completed')
  end

  def attach_recording!(target_call)
    target_call.recording.attach(io: StringIO.new('AUDIO'), filename: 'call.wav', content_type: 'audio/wav')
  end

  it 'does nothing when the call no longer exists' do
    expect { described_class.perform_now(call.id + 1) }.not_to raise_error
    expect(CallAnalysis.count).to eq(0)
  end

  it 'marks recording_missing when the call has no recording attached' do
    call.update!(transcript_segments: [{ speaker: 'Agent', start_seconds: 0, text: 'hola' }])

    described_class.perform_now(call.id)

    record = CallAnalysis.find_by(call: call)
    expect(record.status).to eq('failed')
    expect(record.error_step).to eq('recording_missing')
  end

  it 'marks transcript_unavailable when there are no transcript segments' do
    attach_recording!(call)

    described_class.perform_now(call.id)

    record = CallAnalysis.find_by(call: call)
    expect(record.status).to eq('failed')
    expect(record.error_step).to eq('transcript_unavailable')
  end

  it 'marks agent_unidentified when the call has no accepted_by_agent' do
    call.update!(accepted_by_agent: nil, transcript_segments: [{ speaker: 'Agent', start_seconds: 0, text: 'hola' }])
    attach_recording!(call)

    described_class.perform_now(call.id)

    record = CallAnalysis.find_by(call: call)
    expect(record.status).to eq('failed')
    expect(record.error_step).to eq('agent_unidentified')
  end

  context 'with a ready recording and transcript' do
    let(:llm_response) do
      {
        'role' => 'setter', 'conversation_type' => 'prospeccion_inicial', 'confidence' => 'high',
        'confidence_reason' => 'clara', 'intent_level' => 'alta', 'intent_signals' => ['pregunta por unidad'],
        'outcome_type' => 'cita', 'outcome_at' => 1.day.from_now.iso8601, 'outcome_evidence' => 'quedamos el jueves',
        'qualification_map' => {}, 'objections' => [], 'risks' => [], 'contactability' => { 'issue' => false },
        'presentation_quality' => {}, 'role_confidence_note' => 'coincide con role_hint',
        'scorecard_stages' => CallAnalysis::ScorecardConfig.stage_keys('setter').index_with { |_| { 'score' => 80, 'evidence' => 'ok' } }
      }
    end

    before do
      attach_recording!(call)
      call.update!(transcript_segments: [
                     { speaker: 'Agent', start_seconds: 0, end_seconds: 3, text: 'hola' },
                     { speaker: 'Contact', start_seconds: 3, end_seconds: 6, text: 'hola' }
                   ])
      allow_any_instance_of(CallAnalysis::StructuredAnalysisLlmService).to receive(:generate).and_return(llm_response)
    end

    it 'completes the analysis, calculates the scorecard, and enqueues the Zoho note' do
      expect { described_class.perform_now(call.id) }.to have_enqueued_job(CallAnalysis::PublishZohoNoteJob)

      record = CallAnalysis.find_by(call: call)
      expect(record.status).to eq('completed')
      expect(record.role).to eq('setter')
      expect(record.scorecard['total_score']).to eq(80.0)
      expect(record.scorecard['reading']).to eq('solido')
      expect(record.metrics).to be_present
    end

    it 'is idempotent: a retry updates the same row instead of duplicating it' do
      described_class.perform_now(call.id)
      expect(CallAnalysis.where(call: call).count).to eq(1)

      expect_any_instance_of(CallAnalysis::StructuredAnalysisLlmService).not_to receive(:generate)
      described_class.perform_now(call.id)

      expect(CallAnalysis.where(call: call).count).to eq(1)
    end

    context 'when the model reports low confidence' do
      let(:llm_response) { super().merge('confidence' => 'low') }

      it 'completes but flags it for review and does not publish a Zoho note' do
        expect { described_class.perform_now(call.id) }.not_to have_enqueued_job(CallAnalysis::PublishZohoNoteJob)

        record = CallAnalysis.find_by(call: call)
        expect(record.status).to eq('completed')
        expect(record.error_step).to eq('low_confidence')
      end
    end

    context 'when the LLM service returns an error' do
      before { allow_any_instance_of(CallAnalysis::StructuredAnalysisLlmService).to receive(:generate).and_return(error: 'model_error') }

      it 'marks the analysis as failed with that error step' do
        described_class.perform_now(call.id)

        record = CallAnalysis.find_by(call: call)
        expect(record.status).to eq('failed')
        expect(record.error_step).to eq('model_error')
      end
    end
  end
end
