# Resolves a saved contact segment (CustomFilter of type contact, built on the Contacts page) into
# the contacts a WhatsApp campaign would target. Used both when the campaign fires
# (Whatsapp::OneoffCampaignService) and for the audience preview in the campaign form, so the count
# shown before sending is computed exactly like the real send.
class Campaigns::SegmentAudience
  SAMPLE_SIZE = 10

  pattr_initialize [:account!, :segment_id!]

  def segment
    @segment ||= account.custom_filters.contact.find_by(id: segment_id)
  end

  # Contacts matching the segment that have a phone and aren't known to lack WhatsApp. Opt-outs and
  # the cross-campaign cooldown are applied later per contact (Campaigns::RecipientEligibility).
  def contacts
    matching_contacts.where.not(phone_number: [nil, ''])
                     .where("(contacts.additional_attributes->>'wa_valid') IS DISTINCT FROM 'false'")
  end

  def preview
    eligibility = Campaigns::RecipientEligibility.new(campaign: Campaign.new(account_id: account.id))
    opted_out = eligibility.opted_out_keys
    cooldown = eligibility.cooldown_keys
    sendable = contacts.to_a
    blocked, eligible = sendable.partition { |contact| blocked_key?(contact, opted_out | cooldown) }

    {
      total: matching_contacts.count,
      eligible: eligible.size,
      excluded: excluded_counts(sendable.size, blocked, opted_out),
      sample: eligible.first(SAMPLE_SIZE).map { |contact| contact.slice(:id, :name, :phone_number, :last_activity_at) }
    }
  end

  private

  def matching_contacts
    return account.contacts.none if segment.nil?

    @matching_contacts ||= Contacts::FilterService.new(account, nil, segment.query.with_indifferent_access).perform[:contacts]
  end

  def excluded_counts(sendable_count, blocked, opted_out)
    total = matching_contacts.count
    no_phone = matching_contacts.where(phone_number: [nil, '']).count
    opted_out_count = blocked.count { |contact| blocked_key?(contact, opted_out) }

    {
      no_phone: no_phone,
      wa_invalid: total - no_phone - sendable_count,
      opted_out: opted_out_count,
      cooldown: blocked.size - opted_out_count
    }
  end

  def blocked_key?(contact, keys)
    keys.include?(Campaigns::RecipientEligibility.phone_key(contact.phone_number))
  end
end
