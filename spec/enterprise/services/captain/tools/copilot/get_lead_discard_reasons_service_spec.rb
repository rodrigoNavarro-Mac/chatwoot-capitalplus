require 'rails_helper'

RSpec.describe Captain::Tools::Copilot::GetLeadDiscardReasonsService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:service) { described_class.new(assistant, user: user) }

  def discarded_lead(zoho_lead_id, created_at_source:, discard_reason: nil, desarrollo: 'torre-1')
    account.revenue_leads.create!(zoho_lead_id: zoho_lead_id, lead_status: 'Cliente perdido/Descartado',
                                  created_at_source: created_at_source, discard_reason: discard_reason, desarrollo: desarrollo)
  end

  describe '#name' do
    let(:user) { create(:user, :administrator, account: account) }

    it 'returns the correct service name' do
      expect(service.name).to eq('get_lead_discard_reasons')
    end
  end

  describe '#parameters' do
    let(:user) { create(:user, :administrator, account: account) }

    it 'defines year, month and desarrollo parameters' do
      expect(service.parameters.keys).to contain_exactly(:year, :month, :desarrollo)
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
  end

  describe '#execute' do
    let(:user) { create(:user, :administrator, account: account) }

    it 'rejects an out-of-range month' do
      expect(service.execute(year: 2026, month: 13)).to eq('month must be between 1 and 12')
    end

    context 'when there are no discarded leads in that month' do
      it 'returns a not found message' do
        expect(service.execute(year: 2026, month: 9)).to eq('No discarded leads for that period found')
      end
    end

    context 'when there are discarded leads in that month' do
      before do
        discarded_lead('lead-1', created_at_source: Time.zone.local(2026, 9, 5), discard_reason: 'No le interesó')
        discarded_lead('lead-2', created_at_source: Time.zone.local(2026, 9, 10), discard_reason: 'No le interesó')
        discarded_lead('lead-3', created_at_source: Time.zone.local(2026, 9, 15), discard_reason: nil)
        discarded_lead('lead-4', created_at_source: Time.zone.local(2026, 10, 1), discard_reason: 'Fuera de mes')
        discarded_lead('lead-5', created_at_source: Time.zone.local(2026, 9, 20), discard_reason: 'No le interesó', desarrollo: 'torre-2')
      end

      it 'counts reasons only within the requested month, grouping blanks as unspecified' do
        result = service.execute(year: 2026, month: 9)

        expect(result).to include('Total discarded leads: 4')
        expect(result).to include('No le interesó: 3')
        expect(result).to include('Sin motivo registrado: 1')
        expect(result).not_to include('Fuera de mes')
      end

      it 'filters by desarrollo' do
        result = service.execute(year: 2026, month: 9, desarrollo: 'torre-2')

        expect(result).to include('Total discarded leads: 1')
        expect(result).to include('No le interesó: 1')
      end
    end
  end
end
