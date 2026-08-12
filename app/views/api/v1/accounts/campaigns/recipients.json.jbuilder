json.meta do
  json.count @recipients_count
  json.current_page @current_page.to_i
end

json.payload do
  json.array! @recipients do |delivery|
    json.id delivery.id
    json.phone_number delivery.phone_number
    json.name delivery.contact&.name
    json.audience_type delivery.audience_type
    json.status delivery.status
    json.sent_at delivery.sent_at
    json.delivered_at delivery.delivered_at
    json.read_at delivery.read_at
    json.failed_reason delivery.failed_reason
    json.responded delivery.responded_at.present?
    json.responded_at delivery.responded_at
  end
end
