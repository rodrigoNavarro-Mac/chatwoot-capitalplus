require 'rails_helper'

describe RevenueIntelligence::DetectRisksJob do
  let(:account) { create(:account) }

  before do
    account.enable_features!('crm_integration')
    create(:integrations_hook, :zoho_crm, account: account, status: 'enabled')
  end

  describe 'deal_stalled' do
    it 'flags an open deal whose stage has not changed in more than the default threshold (medium severity)' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: 'Contactado', stage_modified_at: 20.days.ago)

      described_class.new.perform

      signal = account.revenue_risk_signals.find_by(signal_type: 'deal_stalled', subject_id: deal.id)
      expect(signal.severity).to eq('medium')
      expect(signal.context['days_stalled']).to eq(20)
    end

    it 'escalates to high severity past double the threshold' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: 'Contactado', stage_modified_at: 35.days.ago)

      described_class.new.perform

      expect(account.revenue_risk_signals.find_by(signal_type: 'deal_stalled', subject_id: deal.id).severity).to eq('high')
    end

    it 'uses a higher threshold for the Apartado stage' do
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: RevenueDeal::RESERVED_STAGE, stage_modified_at: 20.days.ago)

      described_class.new.perform

      expect(account.revenue_risk_signals.where(signal_type: 'deal_stalled')).to be_empty # 20 días < umbral de 30 para Apartado
    end

    it 'does not flag a won or lost deal even if stage_modified_at is old' do
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: RevenueDeal::WON_STAGE, won: true, stage_modified_at: 60.days.ago)

      described_class.new.perform

      expect(account.revenue_risk_signals.where(signal_type: 'deal_stalled')).to be_empty
    end

    it 'resolves a previously flagged deal once it moves stage again' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: 'Contactado', stage_modified_at: 20.days.ago)
      described_class.new.perform
      deal.update!(stage_modified_at: Time.current)

      described_class.new.perform

      signal = account.revenue_risk_signals.find_by(signal_type: 'deal_stalled', subject_id: deal.id)
      expect(signal.resolved_at).to be_present
    end
  end

  describe 'lead_no_contact' do
    it 'flags a lead created more than 24h ago with no first_contact_at' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', created_at_source: 2.days.ago)

      described_class.new.perform

      signal = account.revenue_risk_signals.find_by(signal_type: 'lead_no_contact', subject_id: lead.id)
      expect(signal.severity).to eq('high')
    end

    it 'does not flag a lead that was already contacted' do
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', created_at_source: 2.days.ago, first_contact_at: 1.day.ago)

      described_class.new.perform

      expect(account.revenue_risk_signals.where(signal_type: 'lead_no_contact')).to be_empty
    end

    it 'does not flag a discarded lead' do
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', created_at_source: 2.days.ago, discard_reason: 'No interesado')

      described_class.new.perform

      expect(account.revenue_risk_signals.where(signal_type: 'lead_no_contact')).to be_empty
    end

    it 'does not flag a lead created less than 24h ago' do
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', created_at_source: 2.hours.ago)

      described_class.new.perform

      expect(account.revenue_risk_signals.where(signal_type: 'lead_no_contact')).to be_empty
    end
  end

  describe 'appointment_no_show_unverified' do
    it 'flags a past appointment on a deal with no visit_effective stage event after it' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: 'Contactado')
      appointment = account.revenue_appointments.create!(zoho_event_id: 'evt-1', revenue_deal_id: deal.id, starts_at: 1.day.ago)

      described_class.new.perform

      expect(account.revenue_risk_signals.find_by(signal_type: 'appointment_no_show_unverified', subject_id: appointment.id)).to be_present
    end

    it 'does not flag an appointment whose deal has a visit_effective stage event after it started' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: 'Contactado')
      appointment = account.revenue_appointments.create!(zoho_event_id: 'evt-1', revenue_deal_id: deal.id, starts_at: 1.day.ago)
      visita_stage = V2::Reports::SalesFunnelBuilder::VISITA_EFECTIVA_STAGES.first
      account.revenue_stage_events.create!(zoho_deal_id: deal.zoho_deal_id, revenue_deal_id: deal.id, stage: visita_stage,
                                           entered_at: 12.hours.ago)

      described_class.new.perform

      expect(account.revenue_risk_signals.where(signal_type: 'appointment_no_show_unverified', subject_id: appointment.id)).to be_empty
    end

    it 'does not flag an appointment that is still within the grace period' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', stage: 'Contactado')
      account.revenue_appointments.create!(zoho_event_id: 'evt-1', revenue_deal_id: deal.id, starts_at: 30.minutes.ago)

      described_class.new.perform

      expect(account.revenue_risk_signals.where(signal_type: 'appointment_no_show_unverified')).to be_empty
    end

    it 'does not flag an appointment without a resolved revenue_deal_id' do
      account.revenue_appointments.create!(zoho_event_id: 'evt-1', starts_at: 1.day.ago)

      described_class.new.perform

      expect(account.revenue_risk_signals.where(signal_type: 'appointment_no_show_unverified')).to be_empty
    end
  end

  describe '#perform' do
    it 'only evaluates the given account when an account_id is passed' do
      other_account = create(:account)
      other_account.enable_features!('crm_integration')
      create(:integrations_hook, :zoho_crm, account: other_account, status: 'enabled')
      other_account.revenue_leads.create!(zoho_lead_id: 'lead-other', created_at_source: 2.days.ago)
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', created_at_source: 2.days.ago)

      described_class.new.perform(account.id)

      expect(account.revenue_risk_signals.where(signal_type: 'lead_no_contact')).to exist
      expect(other_account.revenue_risk_signals.where(signal_type: 'lead_no_contact')).to be_empty
    end
  end
end
