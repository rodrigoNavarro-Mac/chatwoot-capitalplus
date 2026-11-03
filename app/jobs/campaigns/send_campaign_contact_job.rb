class Campaigns::SendCampaignContactJob < ApplicationJob
  queue_as :low

  def perform(campaign_id, contact_id, contact_data = nil)
    campaign = Campaign.find_by(id: campaign_id)
    return unless campaign
    return if campaign.paused?
    # Re-checked on every send (not just at scheduling) because a campaign runs for days and the
    # number's quality can drop mid-way; HealthSyncSchedulerJob refreshes it hourly while sending.
    return if Campaigns::AutoPauseService.new(campaign: campaign).check_health!

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
    return unless Campaigns::RecipientEligibility.new(campaign: campaign).eligible?(contact.phone_number)

    service.send_to_contact(contact)
  end

  def send_to_csv_contact(campaign, service, contact_data)
    return if contact_data.blank?

    raw_phone = contact_data['phone_number'].presence || contact_data['phone'].presence
    return if raw_phone.blank?
    return if phone_wa_invalid?(campaign, raw_phone)
    return unless Campaigns::RecipientEligibility.new(campaign: campaign).eligible?(raw_phone)

    service.send_to_csv_contact(contact_data)
  end

  def phone_wa_invalid?(campaign, raw_phone)
    normalized = Whatsapp::CsvContactPhoneNormalizer.new(inbox: campaign.inbox).normalize(raw_phone)
    key = format(Redis::RedisKeys::WA_INVALID_PHONES, account_id: campaign.account_id)
    Redis::Alfred.with { |conn| conn.sismember(key, normalized) }
  rescue StandardError
    false
  end
end
