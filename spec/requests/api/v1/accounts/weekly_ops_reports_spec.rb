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
end
