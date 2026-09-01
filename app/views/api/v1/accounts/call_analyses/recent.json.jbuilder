json.meta do
  json.current_page @call_analyses.current_page
  json.total_pages @call_analyses.total_pages
  json.total_count @total_count
end

json.payload do
  json.array! @call_analyses do |analysis|
    json.id analysis.id
    json.call_id analysis.call_id
    json.inbox_id analysis.inbox_id
    json.agent_id analysis.agent_id
    json.agent_name analysis.agent&.available_name
    json.role analysis.role
    json.conversation_type analysis.conversation_type
    json.confidence analysis.confidence
    json.outcome_type analysis.outcome_type
    json.total_score analysis.total_score
    json.score_reading analysis.score_reading
    json.analyzed_at analysis.analyzed_at
  end
end
