class Channels::Whatsapp::HealthSyncSchedulerJob < ApplicationJob
  queue_as :low

  # Numbers with a WhatsApp campaign still sending are refreshed hourly instead of every 6h, so
  # Campaigns::AutoPauseService#check_health! sees a quality drop before many more sends go out.
  # 55 min, not 1h: this runs from the hourly trigger and the previous sync lands a few seconds
  # after the hour, so a strict 1h threshold would skip every other run.
  CAMPAIGN_SYNC_INTERVAL = 55.minutes
  DEFAULT_SYNC_INTERVAL = 6.hours

  def perform
    Channel::Whatsapp.joins(:account)
                     .merge(Account.active)
                     .where(provider: 'whatsapp_cloud')
                     .where(
                       'phone_number_health_checked_at <= ? OR phone_number_health_checked_at IS NULL ' \
                       'OR (channel_whatsapp.id IN (?) AND phone_number_health_checked_at <= ?)',
                       DEFAULT_SYNC_INTERVAL.ago, channel_ids_with_campaigns_sending, CAMPAIGN_SYNC_INTERVAL.ago
                     )
                     .order(Arel.sql('phone_number_health_checked_at IS NULL DESC, phone_number_health_checked_at ASC'))
                     .limit(Limits::BULK_EXTERNAL_HTTP_CALLS_LIMIT)
                     .each do |channel|
      Channels::Whatsapp::HealthSyncJob.perform_later(channel)
    end
  end

  private

  # A campaign sits `completed` for most of its real send window (see Campaign#pause!), so
  # "still sending" is approximated as: started in the last 14 days with deliveries pending.
  def channel_ids_with_campaigns_sending
    campaigns = Campaign.one_off.where(campaign_status: %i[processing completed])
                        .where('started_at > ?', 14.days.ago)
                        .joins(:inbox).where(inboxes: { channel_type: 'Channel::Whatsapp' })
                        .includes(:inbox)
    ids = campaigns.select { |campaign| campaign.audience_count.to_i > campaign.campaign_message_deliveries.count }
                   .map { |campaign| campaign.inbox.channel_id }
    ids.presence || [0]
  end
end
