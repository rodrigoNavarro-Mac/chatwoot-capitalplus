json.array! @sales_funnel_goals do |goal|
  json.id goal.id
  json.development_key goal.development_key
  json.stage goal.stage
  json.period_month goal.period_month
  json.target_percent goal.target_percent
end
