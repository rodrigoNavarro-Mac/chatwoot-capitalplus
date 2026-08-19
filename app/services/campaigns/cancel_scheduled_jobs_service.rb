# Sweeps Sidekiq's global ScheduledSet for pending Campaigns::SendCampaignContactJob
# entries belonging to a single campaign and deletes them. Used when pausing a campaign:
# without this, jobs already scheduled with the old window/timezone would all fire at
# once the moment Sidekiq's poller re-scans them after a resume. Also used as a safety
# sweep from Campaigns::ResumeCampaignJob (see comment there) — that call site intentionally
# runs while the campaign is already `processing`, so this service itself must stay
# unconditional; callers that only want to act while still paused (Campaigns::CancelScheduledJobsJob)
# are responsible for checking `campaign.paused?` before invoking this.
#
# Uses display_class/display_args (not klass/args) because Sidekiq wraps the real
# ActiveJob arguments in a JobWrapper — comparing against .args directly misses every match.
class Campaigns::CancelScheduledJobsService
  pattr_initialize [:campaign!]

  def perform
    cancelled = 0

    Sidekiq::ScheduledSet.new.each do |job|
      next unless job.display_class == 'Campaigns::SendCampaignContactJob'
      next unless job.display_args.first == campaign.id

      job.delete
      cancelled += 1
    end

    cancelled
  end
end
