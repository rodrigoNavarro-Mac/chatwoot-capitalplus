require 'rails_helper'

RSpec.describe Campaigns::CancelScheduledJobsService do
  let(:account) { create(:account) }
  let(:campaign) { create(:campaign, account: account) }
  let(:other_campaign) { create(:campaign, account: account) }

  # Campaigns::SendCampaignContactJob is normally scheduled through ActiveJob's in-memory
  # TestAdapter (config.active_job.queue_adapter = :test in config/environments/test.rb),
  # which never touches Redis - so Sidekiq::ScheduledSet would always look empty. Switch to
  # the real Sidekiq adapter with Sidekiq::Testing.disable! for this spec so jobs actually
  # land in Redis's schedule set, matching what this service reads in production.
  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :sidekiq
    Sidekiq::Testing.disable!(&example)
    ActiveJob::Base.queue_adapter = original_adapter
  end

  after { Sidekiq::ScheduledSet.new.clear }

  def schedule_job(target_campaign, contact_id, at:)
    Campaigns::SendCampaignContactJob.set(wait_until: at).perform_later(target_campaign.id, contact_id)
  end

  it 'deletes only the scheduled jobs belonging to the given campaign' do
    schedule_job(campaign, 1, at: 1.hour.from_now)
    schedule_job(campaign, 2, at: 2.hours.from_now)
    schedule_job(other_campaign, 3, at: 1.hour.from_now)

    expect(Sidekiq::ScheduledSet.new.size).to eq 3

    cancelled = described_class.new(campaign: campaign).perform

    expect(cancelled).to eq 2
    remaining_campaign_ids = Sidekiq::ScheduledSet.new.map { |job| job.display_args.first }
    expect(remaining_campaign_ids).to eq [other_campaign.id]
  end

  it 'is idempotent' do
    schedule_job(campaign, 1, at: 1.hour.from_now)

    described_class.new(campaign: campaign).perform
    second_pass = described_class.new(campaign: campaign).perform

    expect(second_pass).to eq 0
  end
end
