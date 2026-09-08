require 'rails_helper'

RSpec.describe Api::V2::Accounts::RevenueIntelligenceController, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'PATCH /api/v2/accounts/{account.id}/revenue_intelligence/identity_conflicts/:id/resolve' do
    let(:conflict) { account.revenue_identity_conflicts.create!(conflict_type: 'multiple_candidates') }

    context 'when authenticated and authorized' do
      it 'marks the conflict resolved and returns resolved: true' do
        patch "/api/v2/accounts/#{account.id}/revenue_intelligence/identity_conflicts/#{conflict.id}/resolve",
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['resolved']).to be(true)
        expect(conflict.reload.resolved).to be(true)
        expect(conflict.resolved_at).to be_present
      end

      it 'also resolves the mirrored open risk signal so it disappears from the UI immediately' do
        signal = account.revenue_risk_signals.create!(category: 'data_quality', signal_type: 'unresolved_identity_conflict',
                                                      subject_type: 'RevenueIdentityConflict', subject_id: conflict.id,
                                                      first_detected_at: Time.current, detected_at: Time.current)

        patch "/api/v2/accounts/#{account.id}/revenue_intelligence/identity_conflicts/#{conflict.id}/resolve",
              headers: admin.create_new_auth_token, as: :json

        expect(signal.reload.resolved_at).to be_present
      end
    end

    context 'when the user is not an administrator' do
      it 'returns unauthorized' do
        patch "/api/v2/accounts/#{account.id}/revenue_intelligence/identity_conflicts/#{conflict.id}/resolve",
              headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(conflict.reload.resolved).to be(false)
      end
    end
  end

  describe 'POST /api/v2/accounts/{account.id}/revenue_intelligence/deals/:id/relink_lead' do
    context 'when a synced lead\'s Converted_Deal points to this deal' do
      it 'links the deal to that lead, copies its Meta Ads attribution, and resolves the mirrored signal' do
        lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', raw_payload: { 'Converted_Deal' => { 'id' => 'deal-1' } },
                                             campaign_name: 'Campaña Q1', platform: 'Meta')
        deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1')
        signal = account.revenue_risk_signals.create!(category: 'data_quality', signal_type: 'deal_without_lead',
                                                      subject_type: 'RevenueDeal', subject_id: deal.id,
                                                      first_detected_at: Time.current, detected_at: Time.current)

        post "/api/v2/accounts/#{account.id}/revenue_intelligence/deals/#{deal.id}/relink_lead",
             headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['linked']).to be(true)
        expect(deal.reload).to have_attributes(revenue_lead_id: lead.id, campaign_name: 'Campaña Q1', platform: 'Meta')
        expect(signal.reload.resolved_at).to be_present
      end
    end

    context 'when no synced lead points to this deal' do
      it 'returns linked: false without raising' do
        deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1')

        post "/api/v2/accounts/#{account.id}/revenue_intelligence/deals/#{deal.id}/relink_lead",
             headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['linked']).to be(false)
        expect(deal.reload.revenue_lead_id).to be_nil
      end
    end

    context 'when the deal already has a revenue_lead_id' do
      it 'returns linked: true without needing a matching lead (idempotent)' do
        lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1')
        deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', revenue_lead_id: lead.id)

        post "/api/v2/accounts/#{account.id}/revenue_intelligence/deals/#{deal.id}/relink_lead",
             headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['linked']).to be(true)
      end
    end

    context 'when the user is not an administrator' do
      it 'returns unauthorized' do
        deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1')

        post "/api/v2/accounts/#{account.id}/revenue_intelligence/deals/#{deal.id}/relink_lead",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v2/accounts/{account.id}/revenue_intelligence/sync_now' do
    # test.rb fuerza Rails.cache a :null_store (ver config/environments/test.rb) — exist?/write
    # reales son no-ops ahí, así que el caso "throttled" se verifica con un stub explícito, mismo
    # patrón ya usado en spec/jobs/inboxes/fetch_imap_emails_job_spec.rb para este mismo problema.
    context 'when authenticated and authorized' do
      it 'enqueues the leads and deals sync jobs and returns queued: true' do
        expect do
          post "/api/v2/accounts/#{account.id}/revenue_intelligence/sync_now", headers: admin.create_new_auth_token, as: :json
        end.to have_enqueued_job(RevenueIntelligence::SyncZohoLeadsJob).with(account.id)
           .and have_enqueued_job(RevenueIntelligence::SyncZohoDealsJob).with(account.id)

        expect(response.parsed_body['queued']).to be(true)
      end

      it 'throttles when a sync was already triggered recently, without enqueueing new jobs' do
        allow(Rails.cache).to receive(:exist?).with("revenue_intelligence_sync_now:#{account.id}").and_return(true)

        expect do
          post "/api/v2/accounts/#{account.id}/revenue_intelligence/sync_now", headers: admin.create_new_auth_token, as: :json
        end.not_to have_enqueued_job(RevenueIntelligence::SyncZohoLeadsJob)

        expect(response).to have_http_status(:too_many_requests)
        expect(response.parsed_body['queued']).to be(false)
      end
    end

    context 'when the user is not an administrator' do
      it 'returns unauthorized' do
        post "/api/v2/accounts/#{account.id}/revenue_intelligence/sync_now", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
