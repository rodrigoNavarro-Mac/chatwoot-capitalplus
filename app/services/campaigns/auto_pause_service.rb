# Pauses a WhatsApp campaign on its own when Meta signals the number is at risk of being
# restricted (quality drop, spam/rate-limit errors, account locked). Same effect as the
# manual pause endpoint, plus a `pause_reason` the UI shows so the team knows why it stopped.
#
# Motivation: campaign 9 (Aug 2026) kept sending for hours while 131049 rejections climbed
# to 63% of the day's sends, until Meta answered with 131031 "Business Account locked".
class Campaigns::AutoPauseService
  # A single one of these is enough to stop: they mean Meta is already throttling or
  # restricting the business account / phone number.
  IMMEDIATE_PAUSE_ERROR_CODES = [
    131_031, # Business Account locked
    131_048, # Spam rate limit hit
    131_056, # Pair rate limit (too many messages to the same user)
    130_429, # Throughput rate limit
    368      # Temporarily blocked for policies violations
  ].freeze

  # 131049 ("healthy ecosystem engagement") is a normal per-user marketing cap at low
  # rates, but a sharp rise means recipients are ignoring/blocking the template.
  ECOSYSTEM_ERROR_CODE = 131_049
  ECOSYSTEM_WINDOW = 30
  ECOSYSTEM_MAX_RATIO = 0.4

  pattr_initialize [:campaign!]

  def self.error_code(raw)
    raw.to_s[/\d{3,6}/].to_i
  end

  # Returns true when the campaign got paused by this call. `from_webhook` marks status callbacks,
  # which keep arriving after the last send: those only count while the campaign is still sending.
  def check_error!(code, from_webhook: false)
    code = code.to_i
    return false if from_webhook && !recently_sending?
    return pause!("meta_error:#{code}") if IMMEDIATE_PAUSE_ERROR_CODES.include?(code)
    return pause!("meta_error:#{code}") if code == ECOSYSTEM_ERROR_CODE && ecosystem_ratio_exceeded?

    false
  end

  def check_health!
    health = campaign.inbox.channel.try(:phone_number_health).to_h.with_indifferent_access
    return false unless risky_health?(health)

    pause!("number_health:#{health[:quality_rating]}/#{health[:status]}")
  end

  def pause!(reason)
    return false unless campaign.pause!

    campaign.update_columns(pause_reason: reason) # rubocop:disable Rails/SkipsModelValidations
    Rails.logger.warn "[CAMPAIGN AUTO-PAUSE] campaign_id=#{campaign.id} inbox_id=#{campaign.inbox_id} reason=#{reason}"
    Campaigns::CancelScheduledJobsJob.perform_later(campaign.id)
    true
  end

  private

  def risky_health?(health)
    Whatsapp::HealthService::RISKY_QUALITY_RATINGS.include?(health[:quality_rating]) ||
      Whatsapp::HealthService::RISKY_STATUSES.include?(health[:status])
  end

  def recently_sending?
    last_send = campaign.campaign_message_deliveries.maximum(:created_at)
    last_send.present? && last_send > 1.day.ago
  end

  def ecosystem_ratio_exceeded?
    recent = campaign.campaign_message_deliveries.order(created_at: :desc).limit(ECOSYSTEM_WINDOW).pluck(:failed_reason)
    return false if recent.size < ECOSYSTEM_WINDOW

    rejected = recent.count { |reason| self.class.error_code(reason) == ECOSYSTEM_ERROR_CODE }
    rejected.fdiv(recent.size) >= ECOSYSTEM_MAX_RATIO
  end
end
