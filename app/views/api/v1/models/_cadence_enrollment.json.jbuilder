json.id resource.id
json.cadence_name resource.cadence_name
json.current_step resource.current_step
json.status resource.status
json.last_template_sent_at resource.last_template_sent_at
json.last_lead_response_at resource.last_lead_response_at
json.next_action_at resource.next_action_at
json.last_call_task_created_at resource.last_call_task_created_at
json.stopped_reason resource.stopped_reason
json.created_at resource.created_at
json.conversation do
  json.id resource.conversation.display_id
  json.status resource.conversation.status
end
json.contact do
  if resource.contact
    json.id resource.contact.id
    json.name resource.contact.name
    json.phone_number resource.contact.phone_number
  end
end
json.assignee do
  if resource.conversation.assignee
    json.id resource.conversation.assignee.id
    json.name resource.conversation.assignee.name
  end
end
json.has_pending_call_task resource.cadence_call_tasks.pending.exists?
