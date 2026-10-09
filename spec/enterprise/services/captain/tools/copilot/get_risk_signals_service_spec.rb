require 'rails_helper'

RSpec.describe Captain::Tools::Copilot::GetRiskSignalsService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:service) { described_class.new(assistant, user: user) }

  describe '#name' do
    let(:user) { create(:user, :administrator, account: account) }

    it 'returns the correct service name' do
      expect(service.name).to eq('get_risk_signals')
    end
  end

  describe '#parameters' do
    let(:user) { create(:user, :administrator, account: account) }

    it 'defines signal_type, severity and desarrollo parameters' do
      expect(service.parameters.keys).to contain_exactly(:signal_type, :severity, :desarrollo)
    end
  end

  describe '#active?' do
    context 'when user is an administrator' do
      let(:user) { create(:user, :administrator, account: account) }

      it 'returns true' do
        expect(service.active?).to be true
      end
    end

    context 'when user is a regular agent' do
      let(:user) { create(:user, account: account) }

      it 'returns false' do
        expect(service.active?).to be false
      end
    end

    context 'when user is not present' do
      let(:service) { described_class.new(assistant) }
      let(:user) { nil }

      it 'returns false' do
        expect(service.active?).to be false
      end
    end
  end

  describe '#execute' do
    let(:user) { create(:user, :administrator, account: account) }

    context 'when there are no open risk signals' do
      it 'returns a not found message' do
        expect(service.execute).to eq('No risk signals found')
      end
    end

    context 'when there are open risk signals' do
      let(:deal) { account.revenue_deals.create!(zoho_deal_id: 'deal-1', name: 'Depto 302', desarrollo: 'torre-1', stage: 'Apartado') }

      before do
        account.revenue_risk_signals.create!(category: 'risk', signal_type: 'deal_stalled', subject_type: 'RevenueDeal',
                                             subject_id: deal.id, severity: 'high', first_detected_at: Time.current,
                                             detected_at: Time.current, context: { 'days_stalled' => 40, 'stage' => 'Apartado' })
        account.revenue_risk_signals.create!(category: 'risk', signal_type: 'lead_no_contact', subject_type: 'RevenueLead',
                                             subject_id: 999, severity: 'medium', first_detected_at: Time.current,
                                             detected_at: Time.current, context: { 'hours_since_created' => 30 })
        # data_quality signals are a different concern (CRM data hygiene, not sales risk) -- excluded
        account.revenue_risk_signals.create!(category: 'data_quality', signal_type: 'deal_without_lead', subject_type: 'RevenueDeal',
                                             subject_id: deal.id, first_detected_at: Time.current, detected_at: Time.current)
      end

      it 'returns only risk-category signals, skipping ones whose subject no longer exists' do
        result = service.execute

        expect(result).to include('Total open risk signals: 1')
        expect(result).to include("Deal 'Depto 302' stalled 40 days in stage 'Apartado'")
        expect(result).not_to include('deal_without_lead')
      end

      it 'filters by signal_type' do
        result = service.execute(signal_type: 'deal_stalled')

        expect(result).to include('deal_stalled')
      end

      it 'filters by severity' do
        result = service.execute(severity: 'high')

        expect(result).to include('deal_stalled')
      end

      it 'filters by desarrollo' do
        result = service.execute(desarrollo: 'torre-2')

        expect(result).to eq('No risk signals found')
      end
    end
  end
end
