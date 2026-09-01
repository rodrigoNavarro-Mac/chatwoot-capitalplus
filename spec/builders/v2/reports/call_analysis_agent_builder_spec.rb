require 'rails_helper'

describe V2::Reports::CallAnalysisAgentBuilder do
  subject(:result) { described_class.new(account: account, params: {}).build }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:call) { create(:call, account: account, conversation: conversation, accepted_by_agent: agent, provider: :aircall, status: 'completed') }

  it 'groups analyses by agent with conversation type and role distributions' do
    create(:call_analysis, call: call, agent: agent, conversation_type: 'prospeccion_inicial', role: 'setter',
                           scorecard: { 'total_score' => 80.0 })

    row = result[:agents].first
    expect(row[:agent_id]).to eq(agent.id)
    expect(row[:calls_analyzed]).to eq(1)
    expect(row[:average_score]).to eq(80.0)
    expect(row[:conversation_type_distribution]).to eq('prospeccion_inicial' => 1)
    expect(row[:role_distribution]).to eq('setter' => 1)
  end

  it 'tallies objection categories and risk types across analyses' do
    create(:call_analysis, call: call, agent: agent, objections: [{ 'category' => 'financiera' }], risks: [{ 'type' => 'improvisar_condiciones' }])

    expect(result[:objections_tally]).to eq('financiera' => 1)
    expect(result[:risks_tally]).to eq('improvisar_condiciones' => 1)
  end

  it 'excludes low-confidence (voicemail) calls from average_score but still counts them as analyzed' do
    create(:call_analysis, call: call, agent: agent, confidence: 'high', scorecard: { 'total_score' => 80.0 })
    voicemail_call = create(:call, account: account, conversation: conversation, accepted_by_agent: agent, provider: :aircall, status: 'completed')
    create(:call_analysis, call: voicemail_call, agent: agent, confidence: 'low', scorecard: { 'total_score' => 5.0 })

    row = result[:agents].first
    expect(row[:calls_analyzed]).to eq(2)
    expect(row[:voicemail_count]).to eq(1)
    expect(row[:voicemail_percent]).to eq(50.0)
    expect(row[:average_score]).to eq(80.0)
  end

  it 'buckets score_evolution by the week the call happened (call.started_at), not when it was analyzed' do
    old_call = create(:call, account: account, conversation: conversation, accepted_by_agent: agent, provider: :aircall,
                             status: 'completed', started_at: 5.weeks.ago)
    create(:call_analysis, call: old_call, agent: agent, confidence: 'high', scorecard: { 'total_score' => 60.0 },
                           analyzed_at: Time.current)

    expect(result[:score_evolution].keys).to eq([old_call.started_at.to_date.beginning_of_week])
  end

  it 'excludes analyses without an agent from the agent rows' do
    create(:call_analysis, call: call, agent: nil)

    expect(result[:agents]).to be_empty
  end

  it 'returns an empty structure when there is nothing analyzed yet' do
    expect(result).to eq(agents: [], objections_tally: {}, risks_tally: {}, score_evolution: {})
  end
end
