require 'rails_helper'

RSpec.describe Captain::Tools::Copilot::GetSalesFunnelService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:service) { described_class.new(assistant, user: user) }

  def rollup(metric, count:, desarrollo:)
    account.revenue_rollups.create!(date: 5.days.ago.to_date, dimension_type: 'funnel', dimension_id: desarrollo, metric: metric,
                                    count: count, sum_value: 0, desarrollo: desarrollo)
  end

  describe '#name' do
    let(:user) { create(:user, :administrator, account: account) }

    it 'returns the correct service name' do
      expect(service.name).to eq('get_sales_funnel')
    end
  end

  describe '#parameters' do
    let(:user) { create(:user, :administrator, account: account) }

    it 'defines a desarrollo parameter' do
      expect(service.parameters.keys).to contain_exactly(:desarrollo)
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

    context 'when there is no funnel activity' do
      it 'returns a not found message' do
        expect(service.execute).to eq('No sales funnel data found')
      end
    end

    context 'when there is funnel activity' do
      before do
        rollup('lead_created', count: 10, desarrollo: 'torre-1')
        rollup('lead_contacted', count: 6, desarrollo: 'torre-1')
        rollup('lead_created', count: 4, desarrollo: 'torre-2')
      end

      it 'includes every desarrollo with activity when none is given' do
        result = service.execute

        expect(result).to include('Desarrollo: torre-1')
        expect(result).to include('Desarrollo: torre-2')
      end

      it 'filters to a single desarrollo when given' do
        result = service.execute(desarrollo: 'torre-1')

        expect(result).to include('Desarrollo: torre-1')
        expect(result).not_to include('Desarrollo: torre-2')
        expect(result).to include('lead_created: 10 (100.0%, no target set)')
        expect(result).to include('lead_contacted: 6 (60.0%, no target set)')
      end
    end
  end
end
