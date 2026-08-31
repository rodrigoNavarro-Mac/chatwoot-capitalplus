json.id resource.display_id
json.title resource.title
json.description resource.description
json.account_id resource.account_id
json.inbox do
  json.partial! 'api/v1/models/inbox', formats: [:json], resource: resource.inbox
end
json.sender do
  json.partial! 'api/v1/models/agent', formats: [:json], resource: resource.sender if resource.sender.present?
end
json.message resource.message
json.template_params resource.template_params
json.campaign_status resource.campaign_status
json.enabled resource.enabled
json.campaign_type resource.campaign_type
if resource.campaign_type == 'one_off'
  json.scheduled_at resource.scheduled_at.to_i
  json.started_at resource.started_at&.to_i
  json.completed_at resource.completed_at&.to_i
  json.audience resource.audience
  json.audience_type resource.audience_type
  json.delay_min_seconds resource.delay_min_seconds
  json.delay_max_seconds resource.delay_max_seconds
  json.send_window_start resource.send_window_start
  json.send_window_end resource.send_window_end
  json.timezone resource.timezone
  json.has_csv_audience resource.csv_audience.attached?
  json.audience_count resource.audience_count
  # `completed` only means the scheduling loop finished, not that every message went out —
  # the campaign can sit `completed` for its entire real send window (see
  # Campaigns::CampaignProgressEstimator). Expose how many are actually still pending so the
  # campaign list can tell "done" apart from "still sending" without a per-card metrics call.
  json.remaining [resource.audience_count.to_i - resource.campaign_message_deliveries.count, 0].max
end
json.trigger_rules resource.trigger_rules
json.trigger_only_during_business_hours resource.trigger_only_during_business_hours
json.created_at resource.created_at
json.updated_at resource.updated_at
