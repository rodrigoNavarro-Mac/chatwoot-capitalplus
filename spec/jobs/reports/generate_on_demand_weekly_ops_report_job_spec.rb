require 'rails_helper'

RSpec.describe Reports::GenerateOnDemandWeeklyOpsReportJob, type: :job do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp_channel.inbox }
  let(:report) do
    WeeklyOpsReport.create!(account: account, inbox: inbox, status: 'pending', period_start: 7.days.ago.to_date, period_end: Date.current, kpis: {})
  end
  let(:report_params) { { since: 7.days.ago.to_i.to_s, until: 1.minute.from_now.to_i.to_s, period_type: 'week' } }

  it 'builds the kpis, asks the LLM for the analysis and marks the report as completed' do
    allow(V2::Reports::WeeklyOpsReportBuilder).to receive(:new).and_call_original
    allow_any_instance_of(Reports::WeeklyOpsAnalysisLlmService).to receive(:generate).and_return(
      executive_summary: 'Análisis de prueba', card_analyses: { 'contact_time' => 'Nota corta' }
    )

    described_class.perform_now(report.id, report_params)

    report.reload
    expect(report.status).to eq('completed')
    expect(report.llm_analysis).to eq('Análisis de prueba')
    expect(report.card_analyses).to eq('contact_time' => 'Nota corta')
    expect(report.kpis).to be_present
  end

  it 'marks the report as failed and reports the exception when the kpi builder raises' do
    allow(V2::Reports::WeeklyOpsReportBuilder).to receive(:new).and_raise(StandardError, 'boom')
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
    allow(ChatwootExceptionTracker).to receive(:new).with(instance_of(StandardError), account: account).and_return(tracker)

    described_class.perform_now(report.id, report_params)

    expect(report.reload.status).to eq('failed')
    expect(tracker).to have_received(:capture_exception)
  end

  it 'does nothing when the report no longer exists' do
    expect(V2::Reports::WeeklyOpsReportBuilder).not_to receive(:new)

    expect { described_class.perform_now(report.id + 1, report_params) }.not_to raise_error
  end
end
