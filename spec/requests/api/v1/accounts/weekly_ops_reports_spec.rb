require 'rails_helper'

RSpec.describe 'Weekly Ops Reports API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp_channel.inbox }
  let(:params) { { since: 7.days.ago.to_i.to_s, until: 1.minute.from_now.to_i.to_s } }

  before do
    allow_any_instance_of(Reports::WeeklyOpsAnalysisLlmService).to receive(:generate).and_return(
      executive_summary: 'Análisis de prueba', card_analyses: { 'contact_time' => 'Nota corta de prueba' }
    )
  end

  describe 'POST /api/v1/accounts/{account.id}/inboxes/{inbox.id}/weekly_ops_reports' do
    it 'returns unauthorized for agents' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports",
           params: params, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    # Arma los KPIs y le pide al LLM el analisis ejecutivo + mini-analisis de las 15 cards puede
    # tardar mas de los 15s del timeout de Rack::Timeout en produccion (confirmado 2026-08-18) --
    # el request deja el registro en "pending" y encola Reports::GenerateOnDemandWeeklyOpsReportJob
    # en vez de generar todo de forma sincrona.
    it 'immediately persists a pending report and enqueues the background job for administrators' do
      expect do
        post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports",
             params: params, headers: administrator.create_new_auth_token, as: :json
      end.to have_enqueued_job(Reports::GenerateOnDemandWeeklyOpsReportJob)

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:status]).to eq('pending')
      expect(body[:llm_analysis]).to be_nil
      expect(WeeklyOpsReport.where(inbox: inbox).count).to eq(1)
    end

    it 'completes with the executive summary and per-card analyses once the background job runs' do
      perform_enqueued_jobs(only: Reports::GenerateOnDemandWeeklyOpsReportJob) do
        post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports",
             params: params, headers: administrator.create_new_auth_token, as: :json
      end

      report = WeeklyOpsReport.find_by(inbox: inbox)
      expect(report.status).to eq('completed')
      expect(report.llm_analysis).to eq('Análisis de prueba')
      expect(report.card_analyses).to eq('contact_time' => 'Nota corta de prueba')
    end

    it 'marks the report as failed when the job raises' do
      allow(V2::Reports::WeeklyOpsReportBuilder).to receive(:new).and_raise(StandardError, 'boom')
      allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: nil))

      perform_enqueued_jobs(only: Reports::GenerateOnDemandWeeklyOpsReportJob) do
        post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports",
             params: params, headers: administrator.create_new_auth_token, as: :json
      end

      expect(WeeklyOpsReport.find_by(inbox: inbox).status).to eq('failed')
    end

    it 'reuses the same record when generated again for the same period' do
      2.times do
        post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports",
             params: params, headers: administrator.create_new_auth_token, as: :json
      end

      expect(WeeklyOpsReport.where(inbox: inbox).count).to eq(1)
    end

    it 'defaults to period_type week when not given' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports",
           params: params, headers: administrator.create_new_auth_token, as: :json

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:period_type]).to eq('week')
    end

    it 'creates a separate record for a different period_type even with an overlapping period_start' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports",
           params: params, headers: administrator.create_new_auth_token, as: :json

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports",
           params: params.merge(period_type: 'month'), headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(WeeklyOpsReport.where(inbox: inbox).count).to eq(2)
      expect(WeeklyOpsReport.where(inbox: inbox).pluck(:period_type)).to match_array(%w[week month])
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/inboxes/{inbox.id}/weekly_ops_reports' do
    it 'lists the reports generated for the inbox' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports",
           params: params, headers: administrator.create_new_auth_token, as: :json

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body.size).to eq(1)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/inboxes/{inbox.id}/weekly_ops_reports/{id}/pdf' do
    it 'returns a PDF file built with Prawn when there is no letterhead template' do
      perform_enqueued_jobs(only: Reports::GenerateOnDemandWeeklyOpsReportJob) do
        post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports",
             params: params, headers: administrator.create_new_auth_token, as: :json
      end
      report_id = JSON.parse(response.body, symbolize_names: true)[:id]

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports/#{report_id}/pdf",
           params: { chart_images: [] }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq('application/pdf')
      expect(response.body.byteslice(0, 4)).to eq('%PDF')
    end

    it 'builds the report inside the letterhead .docx via Gotenberg when a template is configured' do
      branding = Reports::InboxBranding.new(account: account, inbox: inbox)
      branding.letterhead_template.attach(
        io: File.open(Rails.root.join('spec/fixtures/files/minimal_letterhead.docx')),
        filename: 'minimal_letterhead.docx',
        content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      )
      branding.save!
      stub_request(:post, "#{ENV.fetch('GOTENBERG_URL')}/forms/libreoffice/convert")
        .to_return(status: 200, body: '%PDF-1.4 fake', headers: { 'Content-Type' => 'application/pdf' })

      perform_enqueued_jobs(only: Reports::GenerateOnDemandWeeklyOpsReportJob) do
        post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports",
             params: params, headers: administrator.create_new_auth_token, as: :json
      end
      report_id = JSON.parse(response.body, symbolize_names: true)[:id]

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports/#{report_id}/pdf",
           params: { chart_images: [] }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.body).to eq('%PDF-1.4 fake')
      expect(a_request(:post, "#{ENV.fetch('GOTENBERG_URL')}/forms/libreoffice/convert")).to have_been_made.once
    end

    it 'returns unprocessable_entity when Gotenberg fails' do
      branding = Reports::InboxBranding.new(account: account, inbox: inbox)
      branding.letterhead_template.attach(
        io: File.open(Rails.root.join('spec/fixtures/files/minimal_letterhead.docx')),
        filename: 'minimal_letterhead.docx',
        content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      )
      branding.save!
      stub_request(:post, "#{ENV.fetch('GOTENBERG_URL')}/forms/libreoffice/convert").to_return(status: 500)

      perform_enqueued_jobs(only: Reports::GenerateOnDemandWeeklyOpsReportJob) do
        post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports",
             params: params, headers: administrator.create_new_auth_token, as: :json
      end
      report_id = JSON.parse(response.body, symbolize_names: true)[:id]

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports/#{report_id}/pdf",
           params: { chart_images: [] }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/inboxes/{inbox.id}/weekly_ops_reports/{id}/leads_export' do
    let(:agent_bot) { create(:agent_bot, account: account, bot_config: { 'variables' => { 'desarrollo' => 'Fuego' } }) }
    let!(:report) do
      perform_enqueued_jobs(only: Reports::GenerateOnDemandWeeklyOpsReportJob) do
        post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports",
             params: params, headers: administrator.create_new_auth_token, as: :json
      end
      WeeklyOpsReport.find_by(inbox: inbox)
    end

    before { create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot) }

    it 'returns unauthorized for agents' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports/#{report.id}/leads_export",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    # El builder (V2::Reports::RevenueIntelligenceLeadsExportBuilder) ya tiene su propio spec --
    # aquí solo se cubre que el controller arme since/until/desarrollo correctamente a partir del
    # periodo del reporte y los pase tal cual, y que la respuesta sea un CSV descargable con BOM.
    it 'exports the leads/deals of the exact period of this report as a downloadable CSV' do
      received_params = nil
      fake_builder = instance_double(V2::Reports::RevenueIntelligenceLeadsExportBuilder, build: [])
      allow(V2::Reports::RevenueIntelligenceLeadsExportBuilder).to receive(:new) do |**kwargs|
        received_params = kwargs[:params]
        fake_builder
      end

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports/#{report.id}/leads_export",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq('text/csv')
      expect(response.body.byteslice(0, 3).bytes).to eq([0xEF, 0xBB, 0xBF])
      expect(received_params[:desarrollo]).to eq('Fuego')
      # since/until deben ser STRING, no Integer -- DateRangeHelper#parse_date_time hace
      # DateTime.strptime(datetime, '%s'), que exige un string y revienta con TypeError si se le
      # pasa un Integer directo (bug real en producción 2026-10-07, ver comentario del controller).
      expect([received_params[:since], received_params[:until]]).to all(be_a(String))
      expect(Time.zone.at(received_params[:since].to_i).to_date).to eq(report.period_start)
      expect(Time.zone.at(received_params[:until].to_i).to_date).to eq(report.period_end + 1.day)
    end

    # Sin mock del builder -- esta es la prueba que hubiera detectado el bug real (el mock de
    # arriba nunca invoca DateRangeHelper#range, así que nunca ejecuta el DateTime.strptime que
    # reventaba con un Integer). Usa el mismo patrón que
    # spec/controllers/api/v2/accounts/reports_controller_spec.rb para revenue_intelligence_leads_export.
    it 'actually runs the real builder against a lead created within the report period' do
      account.revenue_leads.create!(zoho_lead_id: 'lead-real-1', desarrollo: 'Fuego', lead_status: 'Contactado',
                                    created_at_source: report.period_start.in_time_zone(inbox.timezone) + 1.day)

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports/#{report.id}/leads_export",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.body).to include('lead-real-1')
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/inboxes/{inbox.id}/weekly_ops_reports/{id}/leads_audit' do
    let(:agent_bot) { create(:agent_bot, account: account, bot_config: { 'variables' => { 'desarrollo' => 'Fuego' } }) }
    let!(:report) do
      perform_enqueued_jobs(only: Reports::GenerateOnDemandWeeklyOpsReportJob) do
        post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports",
             params: params, headers: administrator.create_new_auth_token, as: :json
      end
      WeeklyOpsReport.find_by(inbox: inbox)
    end

    before { create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot) }

    it 'returns unauthorized for agents' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports/#{report.id}/leads_audit",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    # Mismo builder que #leads_export (con su propio spec) -- aquí solo se cubre que esta acción
    # devuelva JSON (no CSV) paginado, para la tabla que se ve sin salir de la página.
    it 'paginates the rows at PER_PAGE, with the real total count and page metadata' do
      rows = Array.new(3) { |i| { zoho_lead_id: "lead-#{i}" } }
      fake_builder = instance_double(V2::Reports::RevenueIntelligenceLeadsExportBuilder, build: rows)
      allow(V2::Reports::RevenueIntelligenceLeadsExportBuilder).to receive(:new).and_return(fake_builder)
      stub_const('Api::V1::Accounts::WeeklyOpsReportsController::PER_PAGE', 2)

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports/#{report.id}/leads_audit",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body).to include(total_count: 3, page: 1, per_page: 2, total_pages: 2)
      expect(body[:rows].size).to eq(2)
    end

    it 'returns the second page when asked, with the remaining row' do
      rows = Array.new(3) { |i| { zoho_lead_id: "lead-#{i}" } }
      fake_builder = instance_double(V2::Reports::RevenueIntelligenceLeadsExportBuilder, build: rows)
      allow(V2::Reports::RevenueIntelligenceLeadsExportBuilder).to receive(:new).and_return(fake_builder)
      stub_const('Api::V1::Accounts::WeeklyOpsReportsController::PER_PAGE', 2)

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports/#{report.id}/leads_audit",
          params: { page: 2 }, headers: administrator.create_new_auth_token, as: :json

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body).to include(page: 2, total_pages: 2)
      expect(body[:rows]).to eq([{ zoho_lead_id: 'lead-2' }])
    end

    # Sin mock del builder -- mismo motivo que el test análogo de #leads_export: el mock de arriba
    # nunca ejecuta DateRangeHelper#range, así que nunca hubiera detectado el TypeError real.
    it 'actually runs the real builder against a lead created within the report period' do
      account.revenue_leads.create!(zoho_lead_id: 'lead-real-1', desarrollo: 'Fuego', lead_status: 'Contactado',
                                    created_at_source: report.period_start.in_time_zone(inbox.timezone) + 1.day)

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports/#{report.id}/leads_audit",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:total_count]).to eq(1)
      expect(body[:rows].first[:zoho_lead_id]).to eq('lead-real-1')
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/inboxes/{inbox.id}/weekly_ops_reports/{id}/no_contact_leads' do
    let(:agent_bot) { create(:agent_bot, account: account, bot_config: { 'variables' => { 'desarrollo' => 'Fuego' } }) }
    let!(:report) do
      perform_enqueued_jobs(only: Reports::GenerateOnDemandWeeklyOpsReportJob) do
        post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports",
             params: params, headers: administrator.create_new_auth_token, as: :json
      end
      WeeklyOpsReport.find_by(inbox: inbox)
    end

    before { create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot) }

    it 'returns unauthorized for agents' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports/#{report.id}/no_contact_leads",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    # El builder (V2::Reports::WeeklyOpsReportNoContactLeadsBuilder) ya tiene su propio spec --
    # aquí solo se cubre que el controller lo invoca con los params correctos del periodo del
    # reporte, igual que leads_export/leads_audit.
    it 'returns the leads of this period with an open lead_no_contact signal' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-no-contact-1', desarrollo: 'Fuego',
                                           created_at_source: report.period_start.in_time_zone(inbox.timezone) + 1.day)
      account.revenue_risk_signals.create!(category: 'risk', signal_type: 'lead_no_contact', subject_type: 'RevenueLead',
                                           subject_id: lead.id, severity: 'high', first_detected_at: Time.current,
                                           detected_at: Time.current, context: { 'hours_since_created' => 30 })

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports/#{report.id}/no_contact_leads",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:total_count]).to eq(1)
      expect(body[:rows].first).to include(zoho_lead_id: 'lead-no-contact-1', horas_sin_contacto: 30)
    end

    it 'forwards the page param to the builder (paginates at PER_PAGE)' do
      stub_const('Api::V1::Accounts::WeeklyOpsReportsController::PER_PAGE', 1)
      3.times do |i|
        lead = account.revenue_leads.create!(zoho_lead_id: "lead-no-contact-#{i}", desarrollo: 'Fuego',
                                             created_at_source: report.period_start.in_time_zone(inbox.timezone) + 1.day)
        account.revenue_risk_signals.create!(category: 'risk', signal_type: 'lead_no_contact', subject_type: 'RevenueLead',
                                             subject_id: lead.id, severity: 'high', first_detected_at: Time.current,
                                             detected_at: Time.current, context: { 'hours_since_created' => 30 })
      end

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/weekly_ops_reports/#{report.id}/no_contact_leads",
          params: { page: 2 }, headers: administrator.create_new_auth_token, as: :json

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body).to include(total_count: 3, page: 2, per_page: 1, total_pages: 3)
      expect(body[:rows].size).to eq(1)
    end
  end
end
