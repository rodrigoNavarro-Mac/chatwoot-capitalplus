require 'rails_helper'

describe V2::Reports::SalesFunnelBuilder do
  let(:account) { create(:account) }
  let(:params) { { since: 20.days.ago.to_i.to_s, until: Time.current.to_i.to_s } }

  # Mismo helper (mismo shape) que spec/builders/v2/reports/revenue_intelligence_builder_spec.rb --
  # desde la unificación de los 3 embudos de ventas este builder solo reempaqueta lo que
  # RevenueIntelligenceBuilder ya calcula a partir de revenue_rollups, así que no hace falta pasar
  # por leads/deals/eventos crudos para probarlo.
  def rollup(dimension_type, dimension_id, metric, count: 1, date: 5.days.ago.to_date, desarrollo: '_all')
    account.revenue_rollups.create!(date: date, dimension_type: dimension_type, dimension_id: dimension_id, metric: metric, count: count,
                                    sum_value: 0, desarrollo: desarrollo)
  end

  def row(rows, desarrollo)
    rows.find { |r| r[:development_key] == desarrollo }
  end

  def stage(rows, desarrollo, stage_name)
    row(rows, desarrollo)[:stages].find { |s| s[:stage] == stage_name }
  end

  describe '#build' do
    it 'returns one row per desarrollo with funnel activity, excluding the internal "_all" fallback' do
      rollup('funnel', 'torre-1', 'lead_created', desarrollo: 'torre-1')
      rollup('funnel', 'torre-2', 'lead_created', desarrollo: 'torre-2')
      rollup('funnel', '_all', 'lead_created', desarrollo: '_all')

      rows = described_class.new(account: account, params: params).build

      expect(rows.map { |r| r[:development_key] }).to contain_exactly('torre-1', 'torre-2')
    end

    it 'filters to a single desarrollo when given in params' do
      rollup('funnel', 'torre-1', 'lead_created', desarrollo: 'torre-1')
      rollup('funnel', 'torre-2', 'lead_created', desarrollo: 'torre-2')

      rows = described_class.new(account: account, params: params.merge(desarrollo: 'torre-1')).build

      expect(rows.map { |r| r[:development_key] }).to eq(['torre-1'])
    end

    it 'reads the same per-stage counts RevenueIntelligenceBuilder would return for that desarrollo' do
      rollup('funnel', 'torre-1', 'lead_created', count: 10, desarrollo: 'torre-1')
      rollup('funnel', 'torre-1', 'lead_contacted', count: 6, desarrollo: 'torre-1')
      rollup('funnel', 'torre-1', 'deal_created', count: 4, desarrollo: 'torre-1')
      rollup('funnel', 'torre-1', 'visit_effective', count: 2, desarrollo: 'torre-1')
      rollup('funnel', 'torre-1', 'closed_won', count: 1, desarrollo: 'torre-1')

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'torre-1', 'lead_created')[:count]).to eq(10)
      expect(stage(rows, 'torre-1', 'lead_contacted')[:count]).to eq(6)
      expect(stage(rows, 'torre-1', 'deal_created')[:count]).to eq(4)
      expect(stage(rows, 'torre-1', 'visit_effective')[:count]).to eq(2)
      expect(stage(rows, 'torre-1', 'closed_won')[:count]).to eq(1)
    end

    it 'computes actual_percent against the immediately preceding stage of THIS 5-stage sequence (not the 7-stage Overview one)' do
      rollup('funnel', 'torre-1', 'lead_created', count: 10, desarrollo: 'torre-1')
      rollup('funnel', 'torre-1', 'lead_contacted', count: 6, desarrollo: 'torre-1')
      rollup('funnel', 'torre-1', 'deal_created', count: 3, desarrollo: 'torre-1')

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'torre-1', 'lead_created')[:actual_percent]).to eq(100.0)
      expect(stage(rows, 'torre-1', 'lead_contacted')[:actual_percent]).to eq(60.0) # 6 de 10
      expect(stage(rows, 'torre-1', 'deal_created')[:actual_percent]).to eq(50.0) # 3 de 6, no de 10
    end

    it 'attaches the monthly goal and delta for the matching development_key/stage' do
      period_month = Time.zone.at(params[:since].to_i).to_date.beginning_of_month
      create(:sales_funnel_goal, account: account, development_key: 'torre-1', stage: 'lead_created',
                                 period_month: period_month, target_percent: 50)
      rollup('funnel', 'torre-1', 'lead_created', count: 1, desarrollo: 'torre-1')

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'torre-1', 'lead_created')[:target_percent]).to eq(50.0)
      expect(stage(rows, 'torre-1', 'lead_created')[:delta]).to eq(50.0)
    end

    it 'has a nil target_percent/delta when there is no goal configured' do
      rollup('funnel', 'torre-1', 'lead_created', count: 1, desarrollo: 'torre-1')

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'torre-1', 'lead_created')[:target_percent]).to be_nil
      expect(stage(rows, 'torre-1', 'lead_created')[:delta]).to be_nil
    end

    describe 'calls' do
      def whatsapp_inbox_for(desarrollo)
        channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
        agent_bot = create(:agent_bot, account: account, bot_config: { 'variables' => { 'desarrollo' => desarrollo } })
        create(:agent_bot_inbox, inbox: channel.inbox, agent_bot: agent_bot)
        channel.inbox
      end

      it 'aggregates Aircall calls across EVERY WhatsApp inbox linked to the desarrollo (no longer one row per inbox)' do
        rollup('funnel', 'torre-1', 'lead_created', desarrollo: 'torre-1')
        inbox_a = whatsapp_inbox_for('torre-1')
        inbox_b = whatsapp_inbox_for('torre-1')
        create(:call, conversation: create(:conversation, account: account, inbox: inbox_a),
                      provider: :aircall, status: 'completed', started_at: 5.days.ago)
        create(:call, conversation: create(:conversation, account: account, inbox: inbox_b),
                      provider: :aircall, status: 'no_answer', started_at: 5.days.ago)

        rows = described_class.new(account: account, params: params).build

        expect(row(rows, 'torre-1')[:calls]).to eq(total: 2, answered: 1, answered_percent: 50.0)
      end

      it 'reports zero calls for a desarrollo with no linked WhatsApp inbox (e.g. leads captured directly in Zoho)' do
        rollup('funnel', 'torre-1', 'lead_created', desarrollo: 'torre-1')

        rows = described_class.new(account: account, params: params).build

        expect(row(rows, 'torre-1')[:calls]).to eq(total: 0, answered: 0, answered_percent: 0.0)
      end
    end
  end
end
