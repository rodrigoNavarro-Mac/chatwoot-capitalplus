json.array! @weekly_ops_reports do |report|
  json.id report.id
  json.inbox_id report.inbox_id
  json.period_start report.period_start
  json.period_end report.period_end
  json.status report.status
  json.created_at report.created_at
end
