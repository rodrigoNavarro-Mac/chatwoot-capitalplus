# Decides whether a phone may receive a WhatsApp campaign message, beyond the per-campaign
# dedupe that Whatsapp::OneoffCampaignService already does. Two account-wide rules, both meant
# to keep the number's quality rating healthy (user blocks/reports are what get it restricted):
#
# - opt-out: the person asked to stop (BAJA reply, or Meta error 131050) — never send again.
# - cooldown: the person already got a message from another campaign in the last 14 days.
#
# Phones are compared by their last 10 digits so the Mexican 52/521 variants match each other.
class Campaigns::RecipientEligibility
  CROSS_CAMPAIGN_COOLDOWN = 14.days
  OPT_OUT_KEYWORDS = /\b(baja|stop|no me interesa|no quiero recibir)\b/i

  pattr_initialize [:campaign!]

  def self.phone_key(phone)
    phone.to_s.gsub(/\D/, '').last(10)
  end

  def self.opt_out!(account_id, phone)
    key = phone_key(phone)
    return if key.blank?

    Redis::Alfred.with { |conn| conn.sadd(format(Redis::RedisKeys::WA_OPTED_OUT_PHONES, account_id: account_id), key) }
  rescue StandardError => e
    Rails.logger.error "Failed to register campaign opt-out for #{phone}: #{e.message}"
  end

  def self.opt_out_message?(content)
    content.to_s.match?(OPT_OUT_KEYWORDS)
  end

  # Bulk variant used while scheduling: preloads both sets once instead of querying per row.
  def blocked_keys
    @blocked_keys ||= opted_out_keys | cooldown_keys
  end

  def eligible?(phone)
    key = self.class.phone_key(phone)
    return false if key.blank?

    !opted_out?(key) && !in_cooldown?(key)
  end

  private

  def opted_out_keys
    Redis::Alfred.with { |conn| conn.smembers(opt_out_redis_key) }.to_set
  rescue StandardError
    Set.new
  end

  def opted_out?(key)
    Redis::Alfred.with { |conn| conn.sismember(opt_out_redis_key, key) }
  rescue StandardError
    false
  end

  def cooldown_keys
    recent_deliveries.pluck(:phone_number).to_set { |phone| self.class.phone_key(phone) }
  end

  def in_cooldown?(key)
    recent_deliveries.exists?(["regexp_replace(phone_number, '\\D', '', 'g') LIKE ?", "%#{key}"])
  end

  def recent_deliveries
    CampaignMessageDelivery.where(account_id: campaign.account_id)
                           .where.not(campaign_id: campaign.id)
                           .where.not(source_id: nil)
                           .where('sent_at > ?', CROSS_CAMPAIGN_COOLDOWN.ago)
  end

  def opt_out_redis_key
    format(Redis::RedisKeys::WA_OPTED_OUT_PHONES, account_id: campaign.account_id)
  end
end
