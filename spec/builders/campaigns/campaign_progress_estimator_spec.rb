require 'rails_helper'

RSpec.describe Campaigns::CampaignProgressEstimator do
  let(:account) { create(:account) }
  let(:campaign) do
    create(:campaign, account: account, timezone: 'UTC', send_window_start: '09:00', send_window_end: '20:00',
                      delay_min_seconds: 300, delay_max_seconds: 300, audience_count: 10, campaign_status: :processing)
  end

  def create_deliveries(count)
    count.times do |n|
      CampaignMessageDelivery.create!(account: account, campaign: campaign, audience_type: 'csv', phone_number: "+1555000#{n}")
    end
  end

  describe '#build' do
    it 'returns no timing estimate when the campaign is active' do
      campaign.update!(campaign_status: :active)

      result = described_class.new(campaign).build

      expect(result[:status]).to eq 'active'
      expect(result[:next_send_at]).to be_nil
      expect(result[:eta_completion_at]).to be_nil
    end

    it 'still computes a timing estimate once the campaign is completed' do
      # OneoffCampaignService marks the campaign completed right after scheduling every
      # delayed job, well before those jobs actually fire, so this is the state a campaign
      # sits in for most of its real send window.
      create_deliveries(4)
      campaign.update!(campaign_status: :completed)

      travel_to Time.utc(2026, 8, 14, 12, 0, 0) do
        result = described_class.new(campaign).build

        expect(result[:remaining]).to eq 6
        expect(result[:next_send_at]).to eq Time.current.to_i
        expect(result[:eta_completion_at]).to be > result[:next_send_at]
      end
    end

    it 'returns no timing estimate once nothing is remaining' do
      create_deliveries(10)

      result = described_class.new(campaign).build

      expect(result[:remaining]).to eq 0
      expect(result[:next_send_at]).to be_nil
      expect(result[:eta_completion_at]).to be_nil
    end

    it 'computes remaining, next_send_at and eta_completion_at while sends are pending' do
      create_deliveries(4)

      travel_to Time.utc(2026, 8, 14, 12, 0, 0) do
        result = described_class.new(campaign).build

        expect(result[:remaining]).to eq 6
        expect(result[:next_send_at]).to eq Time.current.to_i
        expect(result[:eta_completion_at]).to be > result[:next_send_at]
      end
    end

    it 'pushes next_send_at to tomorrow when called outside the send window' do
      travel_to Time.utc(2026, 8, 14, 21, 0, 0) do
        result = described_class.new(campaign).build

        expect(Time.zone.at(result[:next_send_at]).to_date).to eq Date.new(2026, 8, 15)
      end
    end
  end
end
