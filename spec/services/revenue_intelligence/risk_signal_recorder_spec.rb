require 'rails_helper'

describe RevenueIntelligence::RiskSignalRecorder do
  let(:account) { create(:account) }
  let(:recorder) { described_class.new(account, category: 'risk') }

  describe '#record' do
    it 'creates a new open signal with first_detected_at and detected_at set' do
      recorder.record(signal_type: 'deal_stalled', subject_type: 'RevenueDeal', subject_id: 1, severity: 'high',
                      context: { days_stalled: 21 })

      signal = account.revenue_risk_signals.find_by(signal_type: 'deal_stalled', subject_id: 1)
      expect(signal.category).to eq('risk')
      expect(signal.severity).to eq('high')
      expect(signal.context).to eq({ 'days_stalled' => 21 })
      expect(signal.first_detected_at).to be_present
      expect(signal.resolved_at).to be_nil
    end

    it 'touches detected_at/severity/context on an already-open signal without creating a duplicate' do
      recorder.record(signal_type: 'deal_stalled', subject_type: 'RevenueDeal', subject_id: 1, severity: 'medium')
      first_detected_at = account.revenue_risk_signals.find_by(subject_id: 1).first_detected_at

      travel_to(1.hour.from_now) do
        recorder.record(signal_type: 'deal_stalled', subject_type: 'RevenueDeal', subject_id: 1, severity: 'high')
      end

      expect(account.revenue_risk_signals.where(signal_type: 'deal_stalled', subject_id: 1).count).to eq(1)
      signal = account.revenue_risk_signals.find_by(signal_type: 'deal_stalled', subject_id: 1)
      expect(signal.severity).to eq('high')
      expect(signal.first_detected_at).to be_within(1.second).of(first_detected_at) # no se mueve
      expect(signal.detected_at).to be > signal.first_detected_at
    end

    it 'opens a new signal once a previous one for the same subject was resolved' do
      account.revenue_risk_signals.create!(category: 'risk', signal_type: 'deal_stalled', subject_type: 'RevenueDeal', subject_id: 1,
                                           first_detected_at: 1.day.ago, detected_at: 1.day.ago, resolved_at: 1.hour.ago)

      recorder.record(signal_type: 'deal_stalled', subject_type: 'RevenueDeal', subject_id: 1, severity: 'high')

      expect(account.revenue_risk_signals.where(signal_type: 'deal_stalled', subject_id: 1).count).to eq(2)
      expect(account.revenue_risk_signals.open.where(signal_type: 'deal_stalled', subject_id: 1).count).to eq(1)
    end
  end

  describe '#resolve_stale!' do
    it 'resolves an open signal whose subject is no longer in the active list' do
      recorder.record(signal_type: 'deal_stalled', subject_type: 'RevenueDeal', subject_id: 1)
      recorder.record(signal_type: 'deal_stalled', subject_type: 'RevenueDeal', subject_id: 2)

      recorder.resolve_stale!(signal_type: 'deal_stalled', active_subject_ids: [2])

      expect(account.revenue_risk_signals.find_by(subject_id: 1).resolved_at).to be_present
      expect(account.revenue_risk_signals.find_by(subject_id: 2).resolved_at).to be_nil
    end

    it 'does not touch signals of a different signal_type or category' do
      recorder.record(signal_type: 'deal_stalled', subject_type: 'RevenueDeal', subject_id: 1)
      account.revenue_risk_signals.create!(category: 'risk', signal_type: 'lead_no_contact', subject_type: 'RevenueLead', subject_id: 1,
                                           first_detected_at: Time.current, detected_at: Time.current)
      account.revenue_risk_signals.create!(category: 'data_quality', signal_type: 'deal_stalled', subject_type: 'RevenueDeal',
                                           subject_id: 1, first_detected_at: Time.current, detected_at: Time.current)

      recorder.resolve_stale!(signal_type: 'deal_stalled', active_subject_ids: [])

      expect(account.revenue_risk_signals.find_by(category: 'risk', signal_type: 'deal_stalled').resolved_at).to be_present
      expect(account.revenue_risk_signals.find_by(signal_type: 'lead_no_contact').resolved_at).to be_nil
      expect(account.revenue_risk_signals.find_by(category: 'data_quality').resolved_at).to be_nil
    end

    it 'is a no-op when there are no open signals of that type' do
      expect { recorder.resolve_stale!(signal_type: 'deal_stalled', active_subject_ids: []) }.not_to raise_error
    end
  end
end
