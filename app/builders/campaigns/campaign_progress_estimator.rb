# Estimates campaign send progress from data already in Postgres (audience_count +
# campaign_message_deliveries), rather than scanning Sidekiq's global ScheduledSet on
# every poll of the campaign detail page — that set holds jobs for every account and has
# no per-campaign index, so it's fine for a one-off admin action (see
# Campaigns::CancelScheduledJobsService) but too costly to query on a 15s refresh.
#
# next_send_at/eta_completion_at are therefore *estimates*: they simulate the same
# window-advancing math the scheduler used (Campaigns::SendWindow), using the average of
# delay_min/max_seconds rather than Sidekiq's actual per-contact jitter.
class Campaigns::CampaignProgressEstimator
  # Hard cap on how many contacts we'll walk through the daily-window simulation for the
  # ETA — a runaway audience_count shouldn't turn a metrics request into a slow endpoint.
  MAX_SIMULATED_CONTACTS = 20_000

  attr_reader :campaign

  def initialize(campaign)
    @campaign = campaign
  end

  def build
    {
      status: campaign.campaign_status,
      remaining: remaining,
      # Unix timestamps, matching the convention _campaign.json.jbuilder already uses
      # for scheduled_at, so the frontend can reuse the same messageTimestamp() helper.
      next_send_at: active_with_remaining? ? next_send_at.to_i : nil,
      eta_completion_at: active_with_remaining? ? eta_completion_at.to_i : nil
    }
  end

  private

  # Whatsapp::OneoffCampaignService#perform marks the campaign `completed!` synchronously,
  # right after scheduling every delayed job — long before those jobs actually fire. So
  # `completed` is the state a campaign sits in for most of its real send window; `processing`
  # only lasts as long as the scheduling loop itself.
  def active_with_remaining?
    (campaign.processing? || campaign.completed?) && remaining.positive?
  end

  def remaining
    @remaining ||= [campaign.audience_count.to_i - campaign.campaign_message_deliveries.count, 0].max
  end

  def avg_delay_seconds
    (campaign.delay_min_seconds + campaign.delay_max_seconds) / 2.0
  end

  def next_send_at
    @next_send_at ||= Campaigns::SendWindow.advance_to_window(campaign, Time.current)
  end

  def eta_completion_at
    return next_send_at if remaining <= 1
    return nil if remaining > MAX_SIMULATED_CONTACTS

    time = next_send_at
    (remaining - 1).times do
      time = Campaigns::SendWindow.advance_to_window(campaign, time + avg_delay_seconds.seconds)
    end
    time
  end
end
