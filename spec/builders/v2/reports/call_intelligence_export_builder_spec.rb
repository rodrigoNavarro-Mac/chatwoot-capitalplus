require 'rails_helper'

describe V2::Reports::CallIntelligenceExportBuilder do
  subject(:rows) { described_class.new(account: account, params: params).build }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:inbox) { conversation.inbox }
  let(:call) do
    create(:call, account: account, conversation: conversation, contact: conversation.contact, accepted_by_agent: agent,
                  provider: :aircall, status: 'completed')
  end
  let(:params) { {} }

  it 'exports one row per analyzed call, call facts merged with analysis facts' do
    create(:call_analysis, call: call, agent: agent, objections: [{ 'category' => 'financiera' }], risks: [{ 'type' => 'timing' }],
                           zoho_deal_stage: 'Qualification')

    expect(rows.size).to eq(1)
    row = rows.first
    expect(row).to include(
      call_id: call.id,
      provider_call_id: call.provider_call_id,
      contact_name: conversation.contact.name,
      agent: agent.name,
      role: 'setter',
      conversation_type: 'prospeccion_inicial',
      confidence: 'high',
      outcome_type: 'solo_informacion',
      top_objection: 'financiera',
      top_risk: 'timing',
      zoho_deal_stage: 'Qualification'
    )
  end

  it 'excludes calls without a completed analysis' do
    create(:call_analysis, call: call, agent: agent, status: 'pending')

    expect(rows).to be_empty
  end

  it 'labels a call with no recorded objection/risk as nil, not an exception' do
    create(:call_analysis, call: call, agent: agent, objections: [], risks: [])

    expect(rows.first[:top_objection]).to be_nil
    expect(rows.first[:top_risk]).to be_nil
  end

  context 'when filters are given' do
    let!(:matching) { create(:call_analysis, call: call, agent: agent, confidence: 'high', conversation_type: 'seguimiento_pre_cita') }

    it 'scopes by inbox_id' do
      other_conversation = create(:conversation, account: account)
      other_call = create(:call, account: account, conversation: other_conversation, contact: other_conversation.contact, accepted_by_agent: agent)
      create(:call_analysis, call: other_call, agent: agent)

      result = described_class.new(account: account, params: { inbox_id: inbox.id }).build

      expect(result.size).to eq(1)
      expect(result.first[:call_id]).to eq(call.id)
    end

    it 'scopes by agent_id' do
      other_agent = create(:user, account: account)

      result = described_class.new(account: account, params: { agent_id: other_agent.id }).build

      expect(result).to be_empty
    end

    it 'scopes by confidence' do
      result = described_class.new(account: account, params: { confidence: 'low' }).build

      expect(result).to be_empty
    end

    it 'scopes by conversation_type' do
      result = described_class.new(account: account, params: { conversation_type: 'post_visita' }).build

      expect(result).to be_empty
    end

    # since/until llegan como string desde los query params reales (ver DateRangeHelper#parse_date_time,
    # que espera un string para DateTime.strptime(datetime, '%s') -- un Integer explota con TypeError).
    it 'scopes by analyzed_at range (since/until)' do
      matching.update!(analyzed_at: 10.days.ago)

      in_range = described_class.new(account: account, params: { since: 15.days.ago.to_i.to_s, until: 5.days.ago.to_i.to_s }).build
      out_of_range = described_class.new(account: account, params: { since: 1.day.ago.to_i.to_s, until: Time.current.to_i.to_s }).build

      expect(in_range.size).to eq(1)
      expect(out_of_range).to be_empty
    end
  end
end
