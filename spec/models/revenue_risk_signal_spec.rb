require 'rails_helper'

describe RevenueRiskSignal do
  let(:account) { create(:account) }

  it 'is valid with account, a known category/severity, and required identity fields' do
    signal = described_class.new(account: account, category: 'risk', signal_type: 'deal_stalled', subject_type: 'RevenueDeal',
                                 subject_id: 1, severity: 'high', first_detected_at: Time.current, detected_at: Time.current)

    expect(signal).to be_valid
  end

  it 'rejects an unknown category' do
    signal = described_class.new(account: account, category: 'unknown', signal_type: 'x', subject_type: 'RevenueDeal', subject_id: 1,
                                 first_detected_at: Time.current, detected_at: Time.current)

    expect(signal).not_to be_valid
    expect(signal.errors[:category]).to be_present
  end

  it 'rejects an unknown severity' do
    signal = described_class.new(account: account, category: 'risk', signal_type: 'x', subject_type: 'RevenueDeal', subject_id: 1,
                                 severity: 'critical', first_detected_at: Time.current, detected_at: Time.current)

    expect(signal).not_to be_valid
    expect(signal.errors[:severity]).to be_present
  end

  it 'defaults severity to medium' do
    signal = described_class.create!(account: account, category: 'risk', signal_type: 'x', subject_type: 'RevenueDeal', subject_id: 1,
                                     first_detected_at: Time.current, detected_at: Time.current)

    expect(signal.severity).to eq('medium')
  end

  it 'does not allow two OPEN rows for the same (category, signal_type, subject_type, subject_id)' do
    described_class.create!(account: account, category: 'risk', signal_type: 'deal_stalled', subject_type: 'RevenueDeal', subject_id: 1,
                            first_detected_at: Time.current, detected_at: Time.current)
    duplicate = described_class.new(account: account, category: 'risk', signal_type: 'deal_stalled', subject_type: 'RevenueDeal',
                                    subject_id: 1, first_detected_at: Time.current, detected_at: Time.current)

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'allows a new open row once the previous one for the same subject was resolved' do
    described_class.create!(account: account, category: 'risk', signal_type: 'deal_stalled', subject_type: 'RevenueDeal', subject_id: 1,
                            first_detected_at: Time.current, detected_at: Time.current, resolved_at: Time.current)
    reopened = described_class.new(account: account, category: 'risk', signal_type: 'deal_stalled', subject_type: 'RevenueDeal',
                                   subject_id: 1, first_detected_at: Time.current, detected_at: Time.current)

    expect { reopened.save!(validate: false) }.not_to raise_error
  end

  describe '.open / .resolved' do
    it 'scopes by whether resolved_at is present' do
      open_signal = described_class.create!(account: account, category: 'risk', signal_type: 'a', subject_type: 'RevenueDeal',
                                            subject_id: 1, first_detected_at: Time.current, detected_at: Time.current)
      resolved_signal = described_class.create!(account: account, category: 'risk', signal_type: 'b', subject_type: 'RevenueDeal',
                                                subject_id: 2, first_detected_at: Time.current, detected_at: Time.current,
                                                resolved_at: Time.current)

      expect(account.revenue_risk_signals.open).to contain_exactly(open_signal)
      expect(account.revenue_risk_signals.resolved).to contain_exactly(resolved_signal)
    end
  end
end
