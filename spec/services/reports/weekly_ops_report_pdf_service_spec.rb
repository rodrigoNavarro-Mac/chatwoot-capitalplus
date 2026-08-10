require 'rails_helper'

describe Reports::WeeklyOpsReportPdfService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp_channel.inbox }
  let(:report) do
    WeeklyOpsReport.new(
      account: account, inbox: inbox, period_start: '2026-07-27', period_end: '2026-08-02',
      llm_analysis: 'Texto de análisis de prueba con acentos y eñes.',
      kpis: {
        'inbox_name' => 'Fuego',
        'period' => { 'since' => '2026-07-27', 'until' => '2026-08-02' },
        'volume' => { 'new_conversations' => 42 },
        'contact_time' => { 'first_response' => 3.5, 'reply_time' => 5.1 },
        'by_advisor' => [
          { 'user_id' => 1, 'name' => 'Elizabeth', 'conversations_count' => 12,
            'contact_time' => { 'first_response' => 8.0, 'reply_time' => 4.2 } }
        ],
        'zoho_leads' => {
          'total' => 4,
          'by_status' => { 'Contactado' => 2, 'Intento de contacto' => 2 },
          'by_source' => { 'Facebook Ads' => 3, 'Google Ads' => 1 },
          'discard_reasons' => {},
          'quality_leads_count' => 2,
          'quality_leads_percent' => 50.0
        },
        'cadences' => { 'total_enrollments' => 30, 'response_rate' => 62.5 },
        'campaigns' => { 'messages_sent' => 100 }
      }
    )
  end

  it 'renders a non-empty PDF' do
    io = described_class.new(weekly_ops_report: report).generate

    expect(io.read.byteslice(0, 4)).to eq('%PDF')
  end

  it 'renders fine when there is no by_advisor breakdown' do
    report.kpis = report.kpis.except('by_advisor')

    io = described_class.new(weekly_ops_report: report).generate

    expect(io.read.byteslice(0, 4)).to eq('%PDF')
  end

  it 'renders fine when there is no zoho_leads breakdown' do
    report.kpis = report.kpis.except('zoho_leads')

    io = described_class.new(weekly_ops_report: report).generate

    expect(io.read.byteslice(0, 4)).to eq('%PDF')
  end

  it 'uses the branding accent color when given' do
    branding = Reports::InboxBranding.new(account: account, inbox: inbox, accent_color: '#abcdef')

    io = described_class.new(weekly_ops_report: report, branding: branding).generate

    expect(io.size).to be_positive
  end
end
