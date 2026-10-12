require 'rails_helper'

RSpec.describe Captain::Tools::Copilot::GetLeadDiscardReasonsService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:service) { described_class.new(assistant, user: user) }

  def discarded_lead(zoho_lead_id, created_at_source:, discard_reason: nil, desarrollo: 'torre-1')
    account.revenue_leads.create!(zoho_lead_id: zoho_lead_id, lead_status: 'Cliente perdido/Descartado',
                                  created_at_source: created_at_source, discard_reason: discard_reason, desarrollo: desarrollo)
  end

  around do |example|
    travel_to(Time.utc(2026, 10, 12, 18, 0, 0)) { example.run } # lunes 2026-10-12 en CDMX (UTC-6)
  end

  describe '#name' do
    let(:user) { create(:user, :administrator, account: account) }

    it 'returns the correct service name' do
      expect(service.name).to eq('get_lead_discard_reasons')
    end
  end

  describe '#parameters' do
    let(:user) { create(:user, :administrator, account: account) }

    it 'defines period, since, until_date and desarrollo parameters' do
      expect(service.parameters.keys).to contain_exactly(:period, :since, :until_date, :desarrollo)
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

    it 'rejects an unknown period' do
      expect(service.execute(period: 'last_year')).to eq('period must be one of: this_week, last_week, this_month, last_month')
    end

    it 'rejects an invalid since/until_date' do
      expect(service.execute(since: 'not-a-date', until_date: '2026-09-30')).to eq('since/until_date must be valid dates in YYYY-MM-DD format')
    end

    context 'when there are no discarded leads in the resolved range' do
      it 'returns a not found message' do
        expect(service.execute(period: 'this_month')).to eq('No discarded leads for that period found')
      end
    end

    context 'with discarded leads across different periods' do
      before do
        # "hoy" congelado en lunes 2026-10-12 CDMX; semana pasada = lun 2026-10-05 a dom 2026-10-11
        discarded_lead('lead-last-week', created_at_source: Time.zone.local(2026, 10, 8, 12), discard_reason: 'No le interesó')
        # 20:00 UTC = 14:00 CDMX, sin ambiguedad de dia
        discarded_lead('lead-this-week', created_at_source: Time.zone.local(2026, 10, 12, 20), discard_reason: 'No le interesó')
        discarded_lead('lead-sep-1', created_at_source: Time.zone.local(2026, 9, 5), discard_reason: 'No le interesó')
        discarded_lead('lead-sep-2', created_at_source: Time.zone.local(2026, 9, 20), discard_reason: nil)
        discarded_lead('lead-sep-other-desarrollo', created_at_source: Time.zone.local(2026, 9, 10), discard_reason: 'No le interesó',
                                                    desarrollo: 'torre-2')
      end

      it 'resolves "last_week" as the previous Monday-Sunday in CDMX time' do
        result = service.execute(period: 'last_week')

        expect(result).to include('Total discarded leads: 1')
        expect(result).to include('No le interesó: 1')
      end

      it 'resolves "this_week" relative to "today"' do
        result = service.execute(period: 'this_week')

        expect(result).to include('Total discarded leads: 1')
      end

      it 'accepts an explicit since/until_date range and groups blanks as unspecified' do
        result = service.execute(since: '2026-09-01', until_date: '2026-09-30')

        expect(result).to include('Total discarded leads: 3')
        expect(result).to include('No le interesó: 2')
        expect(result).to include('Sin motivo registrado: 1')
      end

      it 'filters by desarrollo' do
        result = service.execute(since: '2026-09-01', until_date: '2026-09-30', desarrollo: 'torre-2')

        expect(result).to include('Total discarded leads: 1')
      end
    end
  end
end
