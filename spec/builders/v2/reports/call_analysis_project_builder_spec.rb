require 'rails_helper'

describe V2::Reports::CallAnalysisProjectBuilder do
  subject(:result) { described_class.new(account: account, inbox: inbox, params: {}).build }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:inbox) { conversation.inbox }
  let(:call) { create(:call, account: account, conversation: conversation, accepted_by_agent: agent, provider: :aircall, status: 'completed') }

  it 'counts analyzed calls for the inbox' do
    create(:call_analysis, call: call, agent: agent)

    expect(result[:calls_analyzed]).to eq(1)
  end

  it 'tallies dominant objections and recurrent risks' do
    create(:call_analysis, call: call, agent: agent, objections: [{ 'category' => 'financiera' }], risks: [{ 'type' => 'urgencia_antes_de_valor' }])

    expect(result[:objections_dominant]).to eq('financiera' => 1)
    expect(result[:risks_recurrent]).to eq('urgencia_antes_de_valor' => 1)
  end

  it 'summarizes stalled leads (sin_avance) by their top objection' do
    create(:call_analysis, call: call, agent: agent, outcome_type: 'sin_avance', objections: [{ 'category' => 'timing' }])

    expect(result[:loss_reasons]).to eq(total_sin_avance: 1, by_top_objection: { 'timing' => 1 })
  end

  it 'labels a stalled lead with no recorded objection explicitly' do
    create(:call_analysis, call: call, agent: agent, outcome_type: 'sin_avance', objections: [])

    expect(result[:loss_reasons][:by_top_objection]).to eq('sin_objecion_registrada' => 1)
  end

  it 'compares the Zoho stage snapshot against calls that resulted in an appointment' do
    create(:call_analysis, call: call, agent: agent, outcome_type: 'cita', zoho_deal_stage: 'Qualification')

    expect(result[:crm_vs_conversation_mismatch]).to eq('Qualification' => 1)
  end

  it 'scopes strictly to the given inbox' do
    other_inbox_conversation = create(:conversation, account: account)
    other_call = create(:call, account: account, conversation: other_inbox_conversation, accepted_by_agent: agent, provider: :aircall)
    create(:call_analysis, call: other_call, agent: agent)

    expect(result[:calls_analyzed]).to eq(0)
  end
end
