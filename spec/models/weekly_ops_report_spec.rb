require 'rails_helper'

describe WeeklyOpsReport do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp_channel.inbox }

  it 'is valid with an account, inbox and period' do
    report = described_class.new(account: account, inbox: inbox, period_start: 1.week.ago.to_date, period_end: Date.current, kpis: {})

    expect(report).to be_valid
  end

  it 'does not allow two reports for the same inbox and period_start' do
    described_class.create!(account: account, inbox: inbox, period_start: '2026-07-27', period_end: '2026-08-02', kpis: {})
    duplicate = described_class.new(account: account, inbox: inbox, period_start: '2026-07-27', period_end: '2026-08-02', kpis: {})

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:period_start]).to be_present
  end

  it 'defaults to pending status' do
    report = described_class.create!(account: account, inbox: inbox, period_start: 1.week.ago.to_date, period_end: Date.current, kpis: {})

    expect(report.status).to eq('pending')
  end
end
