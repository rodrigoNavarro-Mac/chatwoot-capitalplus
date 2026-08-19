require 'rails_helper'

RSpec.describe Campaigns::CancelScheduledJobsJob do
  let(:account) { create(:account) }
  let(:campaign) { create(:campaign, account: account, campaign_status: :paused) }

  before { allow(Campaign).to receive(:find_by).with(id: campaign.id).and_return(campaign) }

  it 'sweeps scheduled jobs while the campaign is still paused' do
    cancel_service = instance_double(Campaigns::CancelScheduledJobsService, perform: 1)
    expect(Campaigns::CancelScheduledJobsService).to receive(:new).with(campaign: campaign).and_return(cancel_service)

    described_class.perform_now(campaign.id)
  end

  it 'does nothing if the campaign was resumed before this job ran (race with Campaigns::ResumeCampaignJob)' do
    campaign.update!(campaign_status: :processing)

    expect(Campaigns::CancelScheduledJobsService).not_to receive(:new)

    described_class.perform_now(campaign.id)
  end

  it 'does nothing if the campaign no longer exists' do
    allow(Campaign).to receive(:find_by).with(id: -1).and_return(nil)
    expect(Campaigns::CancelScheduledJobsService).not_to receive(:new)

    described_class.perform_now(-1)
  end
end
