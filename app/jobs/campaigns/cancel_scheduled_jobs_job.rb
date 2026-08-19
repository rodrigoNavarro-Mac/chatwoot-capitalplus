class Campaigns::CancelScheduledJobsJob < ApplicationJob
  queue_as :low

  # Enqueued from the pause action, async with no ordering guarantee against a resume that
  # follows shortly after — Sidekiq can run this job before or after Campaigns::ResumeCampaignJob.
  # If it ran after a resume had already rescheduled the campaign, it would delete those
  # brand-new jobs too (confirmed in production: campaign paused then immediately resumed,
  # ended up with zero pending jobs and zero new deliveries, no error anywhere). Re-checking
  # `paused?` here closes that race — once the campaign is no longer paused, this sweep has
  # nothing to do.
  def perform(campaign_id)
    campaign = Campaign.find_by(id: campaign_id)
    return unless campaign
    return unless campaign.paused?

    Campaigns::CancelScheduledJobsService.new(campaign: campaign).perform
  end
end
