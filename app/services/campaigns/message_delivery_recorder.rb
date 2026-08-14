# Persists the outcome of a single WhatsApp campaign send (labels or CSV) as a
# CampaignMessageDelivery row, so it survives past the 7-day Redis TTL the old
# tracking used and can be aggregated into per-campaign metrics.
class Campaigns::MessageDeliveryRecorder
  pattr_initialize [:campaign!]

  def record_labels_delivery(contact:, message:, wa_message_id:, send_error:)
    message.update!(source_id: wa_message_id) if wa_message_id.present?

    campaign.campaign_message_deliveries.create!(
      account_id: campaign.account_id,
      audience_type: 'labels',
      contact_id: contact.id,
      contact_name: contact.name,
      message_id: message.id,
      phone_number: contact.phone_number,
      source_id: wa_message_id,
      **outcome_attrs(wa_message_id, send_error)
    )
  end

  def record_csv_delivery(phone:, contact_name:, wa_message_id:, send_error:)
    campaign.campaign_message_deliveries.create!(
      account_id: campaign.account_id,
      audience_type: 'csv',
      contact_name: contact_name,
      phone_number: phone,
      source_id: wa_message_id,
      **outcome_attrs(wa_message_id, send_error)
    )
  end

  private

  def outcome_attrs(wa_message_id, send_error)
    if wa_message_id.present?
      { status: 'sent', sent_at: Time.current }
    else
      { status: 'failed', failed_at: Time.current, failed_reason: send_error }
    end
  end
end
