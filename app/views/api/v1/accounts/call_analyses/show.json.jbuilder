json.id @call_analysis.id
json.call_id @call_analysis.call_id
json.inbox_id @call_analysis.inbox_id
json.agent_id @call_analysis.agent_id
json.agent_name @call_analysis.agent&.available_name
json.status @call_analysis.status
json.error_step @call_analysis.error_step
json.error_message @call_analysis.error_message
json.attempts @call_analysis.attempts
json.last_attempted_at @call_analysis.last_attempted_at
json.analyzed_at @call_analysis.analyzed_at
json.llm_model @call_analysis.llm_model
json.role @call_analysis.role
json.conversation_type @call_analysis.conversation_type
json.confidence @call_analysis.confidence
json.outcome_type @call_analysis.outcome_type
json.outcome_at @call_analysis.outcome_at
json.intent_level @call_analysis.intent_level
json.qualification_map @call_analysis.qualification_map
json.objections @call_analysis.objections
json.risks @call_analysis.risks
json.evidence @call_analysis.evidence
json.metrics @call_analysis.metrics
json.scorecard @call_analysis.scorecard
json.scorecard_stage_evidence (@call_analysis.llm_raw_response || {})['scorecard_stages']

json.set! :call do
  call = @call_analysis.call
  json.id call.id
  json.conversation_id call.conversation_id
  json.direction call.direction
  json.duration_seconds call.duration_seconds
  json.started_at call.started_at
  json.recording_url call.recording_url
  json.transcript_segments call.transcript_segments
end
