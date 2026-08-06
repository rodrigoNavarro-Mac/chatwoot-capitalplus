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
