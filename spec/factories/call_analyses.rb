FactoryBot.define do
  factory :call_analysis do
    association :call
    account { call.account }
    inbox { call.inbox }
    agent { call.accepted_by_agent }
    provider_call_id { call.provider_call_id }
    status { 'completed' }
    role { 'setter' }
    conversation_type { 'prospeccion_inicial' }
    confidence { 'high' }
    outcome_type { 'solo_informacion' }
    intent_level { 'media' }
    analyzed_at { Time.current }
    scorecard { { 'total_score' => 70.0, 'reading' => 'coaching' } }
  end
end
