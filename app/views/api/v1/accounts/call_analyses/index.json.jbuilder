json.array! @call_analyses do |analysis|
  json.id analysis.id
  json.call_id analysis.call_id
  json.inbox_id analysis.inbox_id
  json.agent_id analysis.agent_id
  json.status analysis.status
  json.error_step analysis.error_step
  json.error_message analysis.error_message
  json.attempts analysis.attempts
  json.last_attempted_at analysis.last_attempted_at
  json.confidence analysis.confidence
end
