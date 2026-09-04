require 'rails_helper'

describe RevenueIntelligence::DetectDataQualityIssuesJob do
  let(:account) { create(:account) }

  before do
    account.enable_features!('crm_integration')
    create(:integrations_hook, :zoho_crm, account: account, status: 'enabled')
  end

  describe 'deal_won_stage_mismatch' do
    it 'flags a deal with won: true but a stage different from WON_STAGE' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: 'Contactado', won: true)

      described_class.new.perform

      expect(account.revenue_risk_signals.find_by(signal_type: 'deal_won_stage_mismatch', subject_id: deal.id)).to be_present
    end

    it 'flags a deal with stage: WON_STAGE but won: false' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: RevenueDeal::WON_STAGE, won: false)

      described_class.new.perform

      expect(account.revenue_risk_signals.find_by(signal_type: 'deal_won_stage_mismatch', subject_id: deal.id)).to be_present
    end

    it 'does not flag a consistent won deal' do
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: RevenueDeal::WON_STAGE, won: true)

      described_class.new.perform

      expect(account.revenue_risk_signals.where(signal_type: 'deal_won_stage_mismatch')).to be_empty
    end

    it 'does not flag a consistent open deal (won: false, stage not WON_STAGE)' do
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: 'Contactado', won: false)

      described_class.new.perform

      expect(account.revenue_risk_signals.where(signal_type: 'deal_won_stage_mismatch')).to be_empty
    end
  end

  describe 'deal_lost_stage_mismatch' do
    it 'flags a deal with lost: true but a stage different from LOST_STAGE' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: 'Contactado', lost: true)

      described_class.new.perform

      expect(account.revenue_risk_signals.find_by(signal_type: 'deal_lost_stage_mismatch', subject_id: deal.id)).to be_present
    end
  end

  describe 'deal_without_lead' do
    it 'flags a deal with no revenue_lead_id' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: 'Contactado')

      described_class.new.perform

      signal = account.revenue_risk_signals.find_by(signal_type: 'deal_without_lead', subject_id: deal.id)
      expect(signal.severity).to eq('low')
    end

    it 'does not flag a deal linked to a lead' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1')
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: 'Contactado', revenue_lead_id: lead.id)

      described_class.new.perform

      expect(account.revenue_risk_signals.where(signal_type: 'deal_without_lead')).to be_empty
    end
  end

  describe 'stage_event_gap' do
    it 'flags a deal whose current stage differs from its most recent stage_event' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: 'Contactado')
      account.revenue_stage_events.create!(zoho_deal_id: deal.zoho_deal_id, revenue_deal_id: deal.id, stage: 'Nuevo lead', entered_at: 2.days.ago)
      account.revenue_stage_events.create!(zoho_deal_id: deal.zoho_deal_id, revenue_deal_id: deal.id, stage: 'Interesado', entered_at: 1.day.ago)

      described_class.new.perform

      signal = account.revenue_risk_signals.find_by(signal_type: 'stage_event_gap', subject_id: deal.id)
      expect(signal.context).to eq({ 'revenue_deals_stage' => 'Contactado', 'last_stage_event_stage' => 'Interesado' })
    end

    it 'does not flag a deal whose stage matches its most recent stage_event' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: 'Interesado')
      account.revenue_stage_events.create!(zoho_deal_id: deal.zoho_deal_id, revenue_deal_id: deal.id, stage: 'Nuevo lead', entered_at: 2.days.ago)
      account.revenue_stage_events.create!(zoho_deal_id: deal.zoho_deal_id, revenue_deal_id: deal.id, stage: 'Interesado', entered_at: 1.day.ago)

      described_class.new.perform

      expect(account.revenue_risk_signals.where(signal_type: 'stage_event_gap')).to be_empty
    end

    it 'does not flag a deal that has no stage_events yet (not a gap, just not synced)' do
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: 'Contactado')

      described_class.new.perform

      expect(account.revenue_risk_signals.where(signal_type: 'stage_event_gap')).to be_empty
    end
  end

  describe 'unresolved_identity_conflict' do
    it 'mirrors an unresolved RevenueIdentityConflict into revenue_risk_signals' do
      conflict = account.revenue_identity_conflicts.create!(conflict_type: 'multiple_candidates', raw_context: { 'phone' => '9981234567' })

      described_class.new.perform

      signal = account.revenue_risk_signals.find_by(signal_type: 'unresolved_identity_conflict', subject_id: conflict.id)
      expect(signal.context).to eq({ 'phone' => '9981234567' })
    end

    it 'resolves the mirrored signal once the underlying conflict is marked resolved' do
      conflict = account.revenue_identity_conflicts.create!(conflict_type: 'multiple_candidates')
      described_class.new.perform
      conflict.update!(resolved: true, resolved_at: Time.current)

      described_class.new.perform

      signal = account.revenue_risk_signals.find_by(signal_type: 'unresolved_identity_conflict', subject_id: conflict.id)
      expect(signal.resolved_at).to be_present
    end

    it 'does not mirror an already-resolved conflict' do
      account.revenue_identity_conflicts.create!(conflict_type: 'multiple_candidates', resolved: true, resolved_at: Time.current)

      described_class.new.perform

      expect(account.revenue_risk_signals.where(signal_type: 'unresolved_identity_conflict')).to be_empty
    end
  end

  describe '#perform' do
    it 'only evaluates the given account when an account_id is passed' do
      other_account = create(:account)
      other_account.enable_features!('crm_integration')
      create(:integrations_hook, :zoho_crm, account: other_account, status: 'enabled')
      other_account.revenue_deals.create!(zoho_deal_id: 'deal-other', stage: 'Contactado')
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: 'Contactado')

      described_class.new.perform(account.id)

      expect(account.revenue_risk_signals.where(signal_type: 'deal_without_lead')).to exist
      expect(other_account.revenue_risk_signals.where(signal_type: 'deal_without_lead')).to be_empty
    end
  end
end
