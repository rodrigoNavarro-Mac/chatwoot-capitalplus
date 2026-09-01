require 'rails_helper'

describe CallAnalysis::ZohoNoteBuilder do
  subject(:builder) { described_class.new(analysis) }

  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:call) do
    create(:call, account: account, conversation: conversation, provider: :aircall, started_at: Time.zone.parse('2026-08-15 10:00'),
                  duration_seconds: 25)
  end
  let(:analysis) do
    create(:call_analysis, call: call, role: 'setter', conversation_type: 'prospeccion_inicial', confidence: confidence,
                           outcome_type: 'sin_avance', intent_level: 'baja', scorecard: { 'total_score' => 0.0, 'reading' => 'critico' })
  end

  context 'with high confidence (a real conversation)' do
    let(:confidence) { 'high' }

    it 'does not include the low-confidence caveat' do
      expect(builder.content).not_to include('Confianza baja')
    end
  end

  context 'with low confidence (voicemail / no real interaction)' do
    let(:confidence) { 'low' }

    it 'leads with a visible caveat so the CRM does not read it as a real conversation analysis' do
      expect(builder.content).to start_with('⚠️ Confianza baja')
    end

    it 'still includes the rest of the summary (outcome, score) for contactability tracking' do
      expect(builder.content).to include('Resultado: sin_avance')
      expect(builder.content).to include('Score: 0.0/100')
    end
  end
end
