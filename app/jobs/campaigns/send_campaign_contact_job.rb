class Campaigns::SendCampaignContactJob < ApplicationJob
  queue_as :low

  def perform(campaign_id, contact_id, contact_data = nil)
    campaign = Campaign.find_by(id: campaign_id)
    return unless campaign

    service = Whatsapp::OneoffCampaignService.new(campaign: campaign)

    if contact_id
      send_to_label_contact(campaign, service, contact_id)
    else
      send_to_csv_contact(campaign, service, contact_data)
    end
  end

  private

  def send_to_label_contact(campaign, service, contact_id)
    contact = campaign.account.contacts.find_by(id: contact_id)
    return unless contact
    return if contact.additional_attributes&.dig('wa_valid') == false

    wa_message_id = service.send_to_contact(contact)
    return if wa_message_id.blank?

    key = format(Redis::RedisKeys::CAMPAIGN_WA_MSG_CONTACT, wa_message_id: wa_message_id)
    Redis::Alfred.setex(key, contact.id.to_s, 7.days.to_i)
  end

  def send_to_csv_contact(campaign, service, contact_data)
    return if contact_data.blank?

    phone = contact_data['phone_number'].presence || contact_data['phone'].presence
    return if phone.blank?
    return if phone_wa_invalid?(campaign.account_id, phone)

    wa_message_id = service.send_to_csv_contact(contact_data)
    return if wa_message_id.blank?

    key = format(Redis::RedisKeys::CAMPAIGN_WA_MSG_PHONE, wa_message_id: wa_message_id)
    Redis::Alfred.setex(key, "#{campaign.account_id}:#{phone}", 7.days.to_i)
  end

  def phone_wa_invalid?(account_id, phone)
    key = format(Redis::RedisKeys::WA_INVALID_PHONES, account_id: account_id)
    Redis::Alfred.with { |conn| conn.sismember(key, phone) }
  rescue StandardError
    false
  end
end
