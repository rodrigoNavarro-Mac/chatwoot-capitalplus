json.array! @conversations do |conversation|
  json.id conversation.id
  json.display_id conversation.display_id
  json.contact do
    json.id conversation.contact.id
    json.name conversation.contact.name
    json.phone_number conversation.contact.phone_number
  end
  json.assignee do
    json.id conversation.assignee.id
    json.name conversation.assignee.name
  end
  json.inbox do
    json.id conversation.inbox.id
    json.name conversation.inbox.name
  end
end
