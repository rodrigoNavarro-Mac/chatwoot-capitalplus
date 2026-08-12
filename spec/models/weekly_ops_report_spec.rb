require 'rails_helper'

describe WeeklyOpsReport do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp_channel.inbox }

  it 'is valid with an account, inbox and period' do
    report = described_class.new(account: account, inbox: inbox, period_start: 1.week.ago.to_date, period_end: Date.current, kpis: {})

    expect(report).to be_valid
  end

  it 'does not allow two reports for the same inbox, period_start and period_type' do
    described_class.create!(account: account, inbox: inbox, period_start: '2026-07-27', period_end: '2026-08-02', kpis: {})
    duplicate = described_class.new(account: account, inbox: inbox, period_start: '2026-07-27', period_end: '2026-08-02', kpis: {})

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:period_start]).to be_present
  end

  it 'allows two reports for the same inbox and period_start when period_type differs' do
    described_class.create!(account: account, inbox: inbox, period_start: '2026-07-01', period_end: '2026-07-31',
                             period_type: 'month', kpis: {})
    quarter_report = described_class.new(account: account, inbox: inbox, period_start: '2026-07-01', period_end: '2026-09-30',
                                          period_type: 'quarter', kpis: {})

    expect(quarter_report).to be_valid
  end

  it 'defaults to week period_type' do
    report = described_class.create!(account: account, inbox: inbox, period_start: 1.week.ago.to_date, period_end: Date.current, kpis: {})

    expect(report.period_type).to eq('week')
  end

  it 'defaults to pending status' do
    report = described_class.create!(account: account, inbox: inbox, period_start: 1.week.ago.to_date, period_end: Date.current, kpis: {})

    expect(report.status).to eq('pending')
  end
end
