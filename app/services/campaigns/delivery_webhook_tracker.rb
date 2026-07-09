# Applies WhatsApp delivery-status callbacks (sent/delivered/read/failed) and inbound
# replies to the CampaignMessageDelivery row created at send time. Works uniformly for
# labels campaigns (which also have a real Message) and CSV campaigns (message-less).
class Campaigns::DeliveryWebhookTracker
  TIMESTAMP_FIELDS = { 'sent' => :sent_at, 'delivered' => :delivered_at, 'read' => :read_at }.freeze

  pattr_initialize [:inbox!]

  def sync_status!(status)
    delivery = CampaignMessageDelivery.find_by(source_id: status[:id])
    return unless delivery

    if status[:status] == 'failed'
      mark_failed(delivery, status[:errors]&.first)
    else
      apply_timestamp(delivery, status[:status])
    end
  end

  # Links an inbound reply to the most recent unanswered campaign send to the same
  # phone number, so CSV campaigns get response tracking once the recipient replies.
  def mark_response!(contact, message, conversation, outgoing_echo: false)
    return if outgoing_echo
    return if contact&.phone_number.blank?

    digits = contact.phone_number.gsub(/\D/, '').last(10)
    return if digits.blank?

    delivery = find_delivery_by_phone_suffix(digits)
    return unless delivery

    delivery.update!(responded_at: Time.current, response_message_id: message.id, response_conversation_id: conversation.id)
  rescue StandardError => e
    Rails.logger.error "Failed to mark campaign response for contact #{contact&.id}: #{e.message}"
  end

  private

  def find_delivery_by_phone_suffix(digits)
    CampaignMessageDelivery
      .where(account_id: inbox.account_id, responded_at: nil)
      .where.not(sent_at: nil)
      .where("regexp_replace(phone_number, '\\D', '', 'g') LIKE ?", "%#{digits}")
      .order(sent_at: :desc)
      .first
  end

  def apply_timestamp(delivery, wa_status)
    field = TIMESTAMP_FIELDS[wa_status]
    return unless field

    value = wa_status == 'sent' ? (delivery.sent_at || Time.current) : Time.current
    delivery.update!({ status: wa_status }.merge(field => value))
  end

  def mark_failed(delivery, error)
    failed_reason = error ? "#{error[:code]}: #{error[:title]}" : nil
    delivery.update!(status: 'failed', failed_at: Time.current, failed_reason: failed_reason)
    mark_wa_invalid(delivery) if error && error[:code].to_i == 131_026
  end

  def mark_wa_invalid(delivery)
    if delivery.audience_type == 'csv'
      key = format(Redis::RedisKeys::WA_INVALID_PHONES, account_id: delivery.account_id)
      Redis::Alfred.with { |conn| conn.sadd(key, delivery.phone_number) }
    else
      mark_contact_wa_invalid(delivery.contact)
    end
  end

  def mark_contact_wa_invalid(contact)
    return unless contact

    attrs = (contact.additional_attributes || {}).merge('wa_valid' => false)
    contact.update_columns(additional_attributes: attrs)
  end
end
