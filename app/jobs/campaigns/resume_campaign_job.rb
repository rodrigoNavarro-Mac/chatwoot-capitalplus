class Campaigns::ResumeCampaignJob < ApplicationJob
  queue_as :low

  def perform(campaign_id)
    campaign = Campaign.find_by(id: campaign_id)
    return unless campaign&.processing?

    # Safety sweep in case any stale jobs from before the pause survived (e.g. a resume
    # racing a still-in-flight cancel job) — cheap no-op when the set is already empty.
    Campaigns::CancelScheduledJobsService.new(campaign: campaign).perform
    campaign.execute_campaign
  end
end
