require 'rails_helper'

describe Reports::WeeklyOpsReportDocxService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp_channel.inbox }
  let(:branding) do
    branding = Reports::InboxBranding.new(account: account, inbox: inbox)
    branding.letterhead_template.attach(
      io: File.open(Rails.root.join('spec/fixtures/files/minimal_letterhead.docx')),
      filename: 'minimal_letterhead.docx',
      content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    )
    branding.save!
    branding
  end
  let(:report) do
    WeeklyOpsReport.new(
      account: account, inbox: inbox, period_start: '2026-07-27', period_end: '2026-08-02',
      llm_analysis: "Primera línea del análisis.\nSegunda línea.",
      kpis: {
        'inbox_name' => 'Fuego', 'period' => { 'since' => '2026-07-27', 'until' => '2026-08-02' },
        'volume' => { 'new_conversations' => 42 }, 'contact_time' => { 'first_response' => 3.5 },
        'by_advisor' => [
          { 'user_id' => 1, 'name' => 'Elizabeth Sánchez', 'conversations_count' => 12,
            'contact_time' => { 'first_response' => 8.0, 'reply_time' => 4.2 } }
        ],
        'cadences' => {}, 'campaigns' => {}
      }
    )
  end

  # PNG rojo de 2x2 válido, para poder verificar que se embebe en word/media/.
  let(:chart_png_base64) do
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR42mP8z8BQz0AEYBxVSF+FABJadwn6/qxjAAAAAElFTkSuQmCC'
  end
  let(:chart_images) { [{ title: 'Tiempos de contacto', data_url: "data:image/png;base64,#{chart_png_base64}" }] }

  def unzip_entries(io)
    entries = {}
    Zip::File.open_buffer(io) do |zip|
      zip.each { |entry| entries[entry.name] = zip.read(entry.name).force_encoding('UTF-8') }
    end
    entries
  end

  it 'preserves the letterhead paragraph already in the template' do
    io = described_class.new(weekly_ops_report: report, branding: branding, chart_images: []).generate

    document_xml = unzip_entries(io)['word/document.xml']
    expect(document_xml).to include('MEMBRETE DE PRUEBA')
  end

  it 'inserts the title, period and KPI summary table into the body' do
    io = described_class.new(weekly_ops_report: report, branding: branding, chart_images: []).generate

    document_xml = unzip_entries(io)['word/document.xml']
    expect(document_xml).to include('Reporte semanal — Fuego')
    expect(document_xml).to include('Periodo: 2026-07-27')
    expect(document_xml).to include('Conversaciones nuevas')
    expect(document_xml).to include('<w:tbl>')
  end

  it 'inserts the by_advisor breakdown as a second table' do
    io = described_class.new(weekly_ops_report: report, branding: branding, chart_images: []).generate

    document_xml = unzip_entries(io)['word/document.xml']
    expect(document_xml).to include('Desglose por asesor')
    expect(document_xml).to include('Elizabeth Sánchez')
    expect(document_xml.scan('<w:tbl>').size).to eq(2)
  end

  it 'omits the by_advisor table when there is no breakdown' do
    report.kpis = report.kpis.except('by_advisor')
    io = described_class.new(weekly_ops_report: report, branding: branding, chart_images: []).generate

    document_xml = unzip_entries(io)['word/document.xml']
    expect(document_xml).not_to include('Desglose por asesor')
    expect(document_xml.scan('<w:tbl>').size).to eq(1)
  end

  it 'inserts the sales funnel stages as a table' do
    report.kpis = report.kpis.merge(
      'pipeline' => {
        'stages' => [
          { 'stage' => 'leads', 'count' => 10, 'actual_percent' => 100.0, 'target_percent' => nil, 'delta' => nil },
          { 'stage' => 'customer_replied', 'count' => 7, 'actual_percent' => 70.0, 'target_percent' => 60.0, 'delta' => 10.0 }
        ]
      }
    )

    io = described_class.new(weekly_ops_report: report, branding: branding, chart_images: []).generate

    document_xml = unzip_entries(io)['word/document.xml']
    expect(document_xml).to include('Embudo de ventas')
    expect(document_xml).to include('Leads totales')
    expect(document_xml).to include('Contestados por el cliente')
  end

  it 'omits the funnel table when there is no pipeline data' do
    io = described_class.new(weekly_ops_report: report, branding: branding, chart_images: []).generate

    document_xml = unzip_entries(io)['word/document.xml']
    expect(document_xml).not_to include('Embudo de ventas')
  end

  it 'inserts the aircall_calls advisor breakdown as a table plus a summary line' do
    report.kpis = report.kpis.merge(
      'aircall_calls' => {
        'total' => 10, 'answered' => 7, 'answered_percent' => 70.0, 'avg_duration_seconds' => 125,
        'incoming' => 6, 'outgoing' => 4,
        'by_advisor' => [
          { 'user_id' => 1, 'name' => 'Elizabeth Sánchez', 'total' => 10, 'answered' => 7, 'answered_percent' => 70.0, 'avg_duration_seconds' => 125 }
        ]
      }
    )

    io = described_class.new(weekly_ops_report: report, branding: branding, chart_images: []).generate

    document_xml = unzip_entries(io)['word/document.xml']
    expect(document_xml).to include('Llamadas por asesor')
    expect(document_xml).to include('Llamadas: 10 (70.0% contestadas, 6 entrantes / 4 salientes)')
    # tabla de resumen + desglose por asesor + tabla de llamadas = 3
    expect(document_xml.scan('<w:tbl>').size).to eq(3)
  end

  it 'omits the aircall_calls table when there is no data' do
    io = described_class.new(weekly_ops_report: report, branding: branding, chart_images: []).generate

    document_xml = unzip_entries(io)['word/document.xml']
    expect(document_xml).not_to include('Llamadas por asesor')
  end

  it 'inserts the zoho_leads distribution tables (pipeline status, source, discard reasons)' do
    report.kpis = report.kpis.merge(
      'zoho_leads' => {
        'total' => 3,
        'by_status' => { 'Contactado' => 2, 'Cliente perdido/Descartado' => 1 },
        'by_source' => { 'Facebook Ads' => 3 },
        'discard_reasons' => { 'NO TUVO PRESUPUESTO' => 1 },
        'quality_leads_count' => 2,
        'quality_leads_percent' => 66.7
      }
    )

    io = described_class.new(weekly_ops_report: report, branding: branding, chart_images: []).generate

    document_xml = unzip_entries(io)['word/document.xml']
    expect(document_xml).to include('Distribución del pipeline')
    expect(document_xml).to include('Fuentes de prospectos')
    expect(document_xml).to include('Motivos de descarte')
    expect(document_xml).to include('Leads de calidad: 2 (66.7%)')
    expect(document_xml).to include('NO TUVO PRESUPUESTO')
    # tabla de resumen + desglose por asesor + 3 tablas de zoho_leads = 5
    expect(document_xml.scan('<w:tbl>').size).to eq(5)
  end

  it 'omits the zoho_leads tables when there is no data' do
    io = described_class.new(weekly_ops_report: report, branding: branding, chart_images: []).generate

    document_xml = unzip_entries(io)['word/document.xml']
    expect(document_xml).not_to include('Distribución del pipeline')
    expect(document_xml).not_to include('Fuentes de prospectos')
    expect(document_xml).not_to include('Motivos de descarte')
  end

  it 'inserts the report-parity metrics (deals created, owner/quality breakdown, weekday-vs-weekend)' do
    report.kpis = report.kpis.deep_merge(
      'by_advisor' => [
        { 'user_id' => 1, 'name' => 'Elizabeth Sánchez', 'conversations_count' => 12,
          'contact_time' => { 'first_response' => 8.0, 'reply_time' => 4.2 },
          'by_period_of_week' => {
            'weekday' => { 'conversations_count' => 10, 'contact_time' => { 'first_response' => 7.0 } },
            'weekend' => { 'conversations_count' => 2, 'contact_time' => { 'first_response' => 15.0 } }
          } }
      ],
      'zoho_leads' => { 'by_owner' => { 'Elizabeth Sánchez' => 3, 'Carlos' => 1 },
                        'quality_by_source' => { 'Facebook Ads' => { 'total' => 3, 'quality' => 2 } } },
      'deals_created' => { 'total' => 1, 'conversion_rate' => 25.0 },
      'conversion_totals' => { 'converted' => 2, 'lost' => 1 },
      'schedule_distribution' => { 'within_business_hours' => 3, 'outside_business_hours' => 1, 'total' => 4 },
      'contact_time_by_period_of_week' => {
        'weekday' => { 'first_response' => 7.0, 'reply_time' => 3.5 },
        'weekend' => { 'first_response' => 15.0, 'reply_time' => 9.0 }
      }
    )

    io = described_class.new(weekly_ops_report: report, branding: branding, chart_images: []).generate

    document_xml = unzip_entries(io)['word/document.xml']
    expect(document_xml).to include('Deals creados: 1 (% conversión: 25.0%)')
    expect(document_xml).to include('Desglose por asesor: entre semana vs fin de semana')
    expect(document_xml).to include('Tiempos de contacto: entre semana vs fin de semana')
    expect(document_xml).to include('Calidad de leads por canal')
    expect(document_xml).to include('Distribución por asesor (Zoho)')
    expect(document_xml).to include('Conversión y descarte: 2 convertidos — 1 descartados')
    expect(document_xml).to include('Leads en horario laboral: 3 — fuera de horario: 1 (de 4 totales)')
  end

  it 'inserts the LLM analysis as paragraphs' do
    io = described_class.new(weekly_ops_report: report, branding: branding, chart_images: []).generate

    document_xml = unzip_entries(io)['word/document.xml']
    expect(document_xml).to include('Primera línea del análisis.')
    expect(document_xml).to include('Segunda línea.')
  end

  it 'embeds chart images under word/media and links them via a relationship' do
    io = described_class.new(weekly_ops_report: report, branding: branding, chart_images: chart_images).generate

    entries = unzip_entries(io)
    media_entries = entries.keys.select { |name| name.start_with?('word/media/') }
    expect(media_entries).not_to be_empty
    expect(entries['word/_rels/document.xml.rels']).to include('relationships/image')
    expect(entries['word/document.xml']).to include('<w:drawing>')
  end

  it 'produces a document.xml that is still well-formed XML' do
    io = described_class.new(weekly_ops_report: report, branding: branding, chart_images: chart_images).generate

    document_xml = unzip_entries(io)['word/document.xml']
    expect { Nokogiri::XML(document_xml, &:strict) }.not_to raise_error
  end
end
