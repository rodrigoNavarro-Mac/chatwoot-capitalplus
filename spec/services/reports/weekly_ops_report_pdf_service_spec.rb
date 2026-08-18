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
        'pipeline' => {
          'stages' => [
            { 'stage' => 'leads', 'count' => 10, 'actual_percent' => 100.0, 'target_percent' => nil, 'delta' => nil },
            { 'stage' => 'customer_replied', 'count' => 7, 'actual_percent' => 70.0, 'target_percent' => 60.0, 'delta' => 10.0 }
          ],
          'calls' => { 'total' => 10, 'answered' => 7, 'answered_percent' => 70.0 }
        },
        'aircall_calls' => {
          'total' => 10, 'answered' => 7, 'answered_percent' => 70.0, 'avg_duration_seconds' => 145,
          'incoming' => 6, 'outgoing' => 4,
          'by_advisor' => [
            { 'user_id' => 1, 'name' => 'Elizabeth', 'total' => 10, 'answered' => 7, 'answered_percent' => 70.0, 'avg_duration_seconds' => 145 }
          ]
        },
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

  it 'renders fine when there is no pipeline breakdown' do
    report.kpis = report.kpis.except('pipeline')

    io = described_class.new(weekly_ops_report: report).generate

    expect(io.read.byteslice(0, 4)).to eq('%PDF')
  end

  it 'renders fine when there is no aircall_calls breakdown' do
    report.kpis = report.kpis.except('aircall_calls')

    io = described_class.new(weekly_ops_report: report).generate

    expect(io.read.byteslice(0, 4)).to eq('%PDF')
  end

  it 'renders fine when there is no zoho_leads breakdown' do
    report.kpis = report.kpis.except('zoho_leads')

    io = described_class.new(weekly_ops_report: report).generate

    expect(io.read.byteslice(0, 4)).to eq('%PDF')
  end

  it 'renders fine with the report-parity metrics (deals, owner/quality breakdown, weekday-vs-weekend)' do
    report.kpis = report.kpis.deep_merge(
      'by_advisor' => [
        { 'user_id' => 1, 'name' => 'Elizabeth', 'conversations_count' => 12,
          'contact_time' => { 'first_response' => 8.0, 'reply_time' => 4.2 },
          'by_period_of_week' => {
            'weekday' => { 'conversations_count' => 10, 'contact_time' => { 'first_response' => 7.0 } },
            'weekend' => { 'conversations_count' => 2, 'contact_time' => { 'first_response' => 15.0 } }
          } }
      ],
      'zoho_leads' => { 'by_owner' => { 'Elizabeth' => 3, 'Carlos' => 1 },
                        'quality_by_source' => { 'Facebook Ads' => { 'total' => 3, 'quality' => 2 } } },
      'deals_created' => { 'total' => 1, 'conversion_rate' => 25.0 },
      'conversion_totals' => { 'converted' => 2, 'lost' => 1 },
      'schedule_distribution' => { 'within_business_hours' => 3, 'outside_business_hours' => 1, 'total' => 4 },
      'contact_time_by_period_of_week' => {
        'weekday' => { 'first_response' => 7.0, 'reply_time' => 3.5 },
        'weekend' => { 'first_response' => 15.0, 'reply_time' => 9.0 }
      }
    )

    io = described_class.new(weekly_ops_report: report).generate

    expect(io.read.byteslice(0, 4)).to eq('%PDF')
  end

  it 'renders fine with per-card AI mini-analyses and chart images carrying a key' do
    report.card_analyses = {
      'pipeline' => 'El embudo se estrecha fuerte en visita efectiva.',
      'by_advisor' => 'Elizabeth concentra casi todas las conversaciones.',
      'conversion_totals' => 'La proporcion de descartados es alta esta semana.'
    }
    chart_images = [
      { key: 'contact_time', title: 'Tiempos de contacto', data_url: nil },
      { key: 'conversion_totals', title: 'Conversión y descarte', data_url: nil }
    ]

    io = described_class.new(weekly_ops_report: report, chart_images: chart_images).generate

    expect(io.read.byteslice(0, 4)).to eq('%PDF')
  end

  it 'uses the branding accent color when given' do
    branding = Reports::InboxBranding.new(account: account, inbox: inbox, accent_color: '#abcdef')

    io = described_class.new(weekly_ops_report: report, branding: branding).generate

    expect(io.size).to be_positive
  end
end
