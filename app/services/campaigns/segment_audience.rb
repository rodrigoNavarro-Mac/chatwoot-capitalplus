# Resolves a saved contact segment (CustomFilter of type contact, built on the Contacts page) into
# the contacts a WhatsApp campaign would target. Used both when the campaign fires
# (Whatsapp::OneoffCampaignService) and for the audience preview in the campaign form, so the count
# shown before sending is computed exactly like the real send.
#
# include_ids / exclude_ids are the per-campaign manual tweaks to the segment: contacts added by hand
# even though they don't match it, and segment members the team doesn't want to message this time.
class Campaigns::SegmentAudience
  SAMPLE_SIZE = 10
  MEMBERS_PER_PAGE = 20

  pattr_initialize [:account!, :segment_id!, :include_ids, :exclude_ids]

  def segment
    @segment ||= account.custom_filters.contact.find_by(id: segment_id)
  end

  # Audience contacts that have a phone and aren't known to lack WhatsApp. Opt-outs and the
  # cross-campaign cooldown are applied later per contact (Campaigns::RecipientEligibility), also to
  # the contacts added by hand.
  def contacts
    audience.where.not(phone_number: [nil, ''])
            .where("(contacts.additional_attributes->>'wa_valid') IS DISTINCT FROM 'false'")
  end

  def preview
    eligibility = Campaigns::RecipientEligibility.new(campaign: Campaign.new(account_id: account.id))
    opted_out = eligibility.opted_out_keys
    cooldown = eligibility.cooldown_keys
    sendable = contacts.to_a
    blocked, eligible = sendable.partition { |contact| blocked_key?(contact, opted_out | cooldown) }

    {
      total: audience.count,
      eligible: eligible.size,
      added: added_ids.size,
      removed: removed_ids.size,
      excluded: excluded_counts(sendable.size, blocked, opted_out),
      sample: eligible.first(SAMPLE_SIZE).map { |contact| contact.slice(:id, :name, :phone_number, :last_activity_at) }
    }
  end

  # Segment members (before the manual tweaks) for the form's "remove contacts" list, searchable by
  # name or phone
  def members(query: nil, page: 1)
    scope = account.contacts.where(id: matching_contacts.select(:id)).order(:name, :id)
    if query.present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(query.strip)}%"
      scope = scope.where('contacts.name ILIKE :term OR contacts.phone_number ILIKE :term', term: term)
    end
    scope.page(page).per(MEMBERS_PER_PAGE)
  end

  private

  def audience
    return account.contacts.none if segment.nil?

    @audience ||= account.contacts.where(id: matching_contacts.select(:id))
                         .or(account.contacts.where(id: Array(include_ids)))
                         .where.not(id: Array(exclude_ids))
  end

  def matching_contacts
    return account.contacts.none if segment.nil?

    @matching_contacts ||= Contacts::FilterService.new(account, nil, segment.query.with_indifferent_access).perform[:contacts]
  end

  # Hand-added contacts that weren't already in the segment (and weren't also removed)
  def added_ids
    return [] if segment.nil? || include_ids.blank?

    account.contacts.where(id: Array(include_ids) - Array(exclude_ids)).where.not(id: matching_contacts.select(:id)).ids
  end

  def removed_ids
    return [] if segment.nil? || exclude_ids.blank?

    account.contacts.where(id: Array(exclude_ids)).where(id: matching_contacts.select(:id)).ids
  end

  def excluded_counts(sendable_count, blocked, opted_out)
    total = audience.count
    no_phone = audience.where(phone_number: [nil, '']).count
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
