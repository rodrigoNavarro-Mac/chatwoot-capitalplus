class Campaigns::CancelScheduledJobsJob < ApplicationJob
  queue_as :low

  def perform(campaign_id)
    campaign = Campaign.find_by(id: campaign_id)
    return unless campaign

    Campaigns::CancelScheduledJobsService.new(campaign: campaign).perform
  end
end
