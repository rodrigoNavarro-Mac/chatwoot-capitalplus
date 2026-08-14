# Shared window-advancing logic used both when scheduling campaign sends
# (Whatsapp::OneoffCampaignService) and when estimating progress
# (Campaigns::CampaignProgressEstimator), so the two can't drift apart.
#
# `campaign.send_window_start`/`send_window_end` are plain "HH:MM" strings with
# no zone of their own — they're interpreted in `campaign.timezone` (defaults to
# "UTC" for campaigns created before this field existed, preserving old behavior).
module Campaigns::SendWindow
  module_function

  def advance_to_window(campaign, time)
    zoned_time = time.in_time_zone(campaign.timezone)
    start_h, start_m = campaign.send_window_start.split(':').map(&:to_i)
    end_h, end_m     = campaign.send_window_end.split(':').map(&:to_i)

    window_start = zoned_time.beginning_of_day + start_h.hours + start_m.minutes
    window_end   = zoned_time.beginning_of_day + end_h.hours   + end_m.minutes

    if zoned_time < window_start
      window_start
    elsif zoned_time >= window_end
      window_start + 1.day
    else
      zoned_time
    end
  end
end
