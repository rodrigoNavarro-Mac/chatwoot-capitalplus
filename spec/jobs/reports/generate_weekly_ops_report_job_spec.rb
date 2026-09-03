require 'rails_helper'

RSpec.describe Reports::GenerateWeeklyOpsReportJob, type: :job do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { whatsapp_channel.inbox }

  before do
    inbox.update!(timezone: 'America/Mexico_City')
    create(:cadence_definition, account: account, inbox: inbox, active: true)
    llm_double = instance_double(Reports::WeeklyOpsAnalysisLlmService, generate: { executive_summary: 'Resumen', card_analyses: {} })
    allow(Reports::WeeklyOpsAnalysisLlmService).to receive(:new).and_return(llm_double)
  end

  # Rails corre en UTC (config.time_zone nunca se configuró) — sin la conversión a la zona del
  # inbox, el borde final de la semana (domingo medianoche EN MÉXICO) caía a las 06:00 UTC del
  # lunes, y una conversación del domingo por la noche en México (guardada de madrugada del lunes
  # en UTC) se excluía de la semana a la que en realidad pertenece. Caso real detectado 2026-09-03.
  it "computes the closed week in the inbox's timezone, so a Sunday-night México conversation (Monday early UTC) still counts" do
    # domingo 30-ago 22:30 en México
    travel_to(Time.utc(2026, 8, 31, 4, 30, 0)) { create(:conversation, account: account, inbox: inbox) }

    travel_to Time.utc(2026, 9, 3, 12, 0, 0) do
      described_class.perform_now

      report = inbox.weekly_ops_reports.find_by!(period_type: 'week')
      expect(report.period_start).to eq(Date.new(2026, 8, 24))
      expect(report.period_end).to eq(Date.new(2026, 8, 30))
      expect(report.kpis.dig('volume', 'new_conversations')).to eq(1)
      expect(report.status).to eq('completed')
    end
  end
end
