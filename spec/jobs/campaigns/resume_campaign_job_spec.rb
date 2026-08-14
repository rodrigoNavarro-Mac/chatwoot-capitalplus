require 'rails_helper'

RSpec.describe Campaigns::ResumeCampaignJob do
  let(:account) { create(:account) }
  let(:campaign) { create(:campaign, account: account, campaign_status: :processing) }

  before { allow(Campaign).to receive(:find_by).with(id: campaign.id).and_return(campaign) }

  it 'sweeps stale scheduled jobs and re-triggers the campaign' do
    cancel_service = instance_double(Campaigns::CancelScheduledJobsService, perform: 0)
    expect(Campaigns::CancelScheduledJobsService).to receive(:new).with(campaign: campaign).and_return(cancel_service)
    expect(campaign).to receive(:execute_campaign)

    described_class.perform_now(campaign.id)
  end

  it 'does nothing if the campaign is not processing' do
    campaign.update!(campaign_status: :paused)

    expect(Campaigns::CancelScheduledJobsService).not_to receive(:new)
    expect(campaign).not_to receive(:execute_campaign)

    described_class.perform_now(campaign.id)
  end

  it 'does nothing if the campaign no longer exists' do
    allow(Campaign).to receive(:find_by).with(id: -1).and_return(nil)
    expect(Campaigns::CancelScheduledJobsService).not_to receive(:new)

    described_class.perform_now(-1)
  end
end
