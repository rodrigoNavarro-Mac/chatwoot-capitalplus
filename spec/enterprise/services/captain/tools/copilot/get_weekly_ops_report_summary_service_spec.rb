require 'rails_helper'

RSpec.describe Captain::Tools::Copilot::GetWeeklyOpsReportSummaryService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:service) { described_class.new(assistant, user: user) }

  def inbox_for_desarrollo(desarrollo)
    inbox = create(:inbox, account: account)
    agent_bot = create(:agent_bot, account: account, bot_config: { 'variables' => { 'desarrollo' => desarrollo } })
    create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
    inbox
  end

  describe '#name' do
    let(:user) { create(:user, :administrator, account: account) }

    it 'returns the correct service name' do
      expect(service.name).to eq('get_weekly_ops_report_summary')
    end
  end

  describe '#parameters' do
    let(:user) { create(:user, :administrator, account: account) }

    it 'defines a required desarrollo parameter' do
      expect(service.parameters.keys).to contain_exactly(:desarrollo)
      expect(service.parameters[:desarrollo].required).to be true
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

    context 'when no inbox is configured for the desarrollo' do
      it 'returns a not found message' do
        expect(service.execute(desarrollo: 'torre-1')).to include('No weekly ops report')
      end
    end

    context 'when the desarrollo has an inbox but no completed report' do
      before { inbox_for_desarrollo('torre-1') }

      it 'returns a not found message' do
        expect(service.execute(desarrollo: 'torre-1')).to include('No weekly ops report')
      end
    end

    context 'when the desarrollo has a completed report' do
      let(:inbox) { inbox_for_desarrollo('torre-1') }

      before do
        WeeklyOpsReport.create!(account: account, inbox: inbox, period_start: 7.days.ago.to_date, period_end: Date.current,
                                period_type: 'week', status: 'completed', kpis: { 'volume' => { 'new_conversations' => 42 } },
                                card_analyses: {}, llm_analysis: 'Semana estable, sin incidentes relevantes.')
      end

      it 'returns the executive summary and key kpis' do
        result = service.execute(desarrollo: 'torre-1')

        expect(result).to include('Desarrollo: torre-1')
        expect(result).to include('New conversations: 42')
        expect(result).to include('Semana estable, sin incidentes relevantes.')
      end

      it 'ignores a pending report for the same desarrollo' do
        WeeklyOpsReport.create!(account: account, inbox: inbox, period_start: 1.day.ago.to_date, period_end: Date.current,
                                period_type: 'week', status: 'pending', kpis: {}, card_analyses: {})

        result = service.execute(desarrollo: 'torre-1')

        expect(result).to include('Semana estable, sin incidentes relevantes.')
      end
    end
  end
end
