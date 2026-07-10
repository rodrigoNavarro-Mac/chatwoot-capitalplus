json.id resource.id
json.step resource.step
json.status resource.status
json.notified_at resource.notified_at
json.completed_at resource.completed_at
json.created_at resource.created_at
json.conversation_id resource.conversation.display_id
json.user do
  if resource.user
    json.id resource.user.id
    json.name resource.user.name
  end
end
