# monitoring
# daily check comparing Chatwoot's recorded WhatsApp campaign delivery stats against what
# Meta's template_analytics API reports, to catch a repeat of the Cluster 777 undercount
# (see Campaigns::MetaAnalyticsReconciler) within a day instead of relying on someone noticing.
class Campaigns::ReconcileMetaAnalyticsJob < ApplicationJob
  queue_as :scheduled_jobs

  LOOKBACK = 7.days

  def perform
    candidate_campaigns.find_each do |campaign|
      Campaigns::MetaAnalyticsReconciler.new(campaign: campaign).perform
    end
  end

  private

  def candidate_campaigns
    Campaign.joins(:inbox)
            .where(inboxes: { channel_type: 'Channel::Whatsapp' })
            .where(campaign_type: :one_off)
            .where('campaigns.created_at > ?', LOOKBACK.ago)
  end
end
