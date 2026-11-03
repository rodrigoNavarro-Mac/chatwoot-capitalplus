require 'rails_helper'

RSpec.describe Campaigns::AutoPauseService do
  subject(:service) { described_class.new(campaign: campaign) }

  let(:account) { create(:account) }
  let!(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:campaign) { create(:campaign, inbox: whatsapp_channel.inbox, account: account, campaign_status: :completed, audience_count: 100) }
  let(:ecosystem_error) { '131049: This message was not delivered to maintain healthy ecosystem engagement.' }

  def create_deliveries(count, failed_reason: nil)
    count.times do
      campaign.campaign_message_deliveries.create!(
        account_id: account.id, audience_type: 'csv', phone_number: "+5255#{SecureRandom.random_number(10**8).to_s.rjust(8, '0')}",
        status: failed_reason ? 'failed' : 'sent', failed_reason: failed_reason, source_id: SecureRandom.hex(8), sent_at: Time.current
      )
    end
  end

  def set_health(quality, status = 'CONNECTED')
    whatsapp_channel.update_columns(phone_number_health: { 'quality_rating' => quality, 'status' => status }) # rubocop:disable Rails/SkipsModelValidations
  end

  describe '#check_error!' do
    it 'pauses immediately on an account-locked error and cancels pending jobs' do
      expect { expect(service.check_error!(131_031)).to be(true) }
        .to have_enqueued_job(Campaigns::CancelScheduledJobsJob).with(campaign.id)

      expect(campaign.reload).to be_paused
      expect(campaign.pause_reason).to eq('meta_error:131031')
    end

    it 'ignores unrelated errors' do
      expect(service.check_error!(131_026)).to be(false)
      expect(campaign.reload).to be_completed
    end

    it 'pauses on 131049 only once it reaches 40% of the last 30 sends' do
      create_deliveries(19)
      create_deliveries(11, failed_reason: ecosystem_error)
      expect(service.check_error!(131_049)).to be(false)

      create_deliveries(1, failed_reason: ecosystem_error)
      expect(service.check_error!(131_049)).to be(true)
      expect(campaign.reload).to be_paused
    end

    it 'ignores late webhooks for a campaign that stopped sending a day ago' do
      create_deliveries(1)
      campaign.campaign_message_deliveries.update_all(created_at: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations

      expect(service.check_error!(131_031, from_webhook: true)).to be(false)
      expect(campaign.reload).to be_completed
    end
  end

  describe '#check_health!' do
    it 'pauses when the number quality is RED' do
      set_health('RED')

      expect(service.check_health!).to be(true)
      expect(campaign.reload.pause_reason).to eq('number_health:RED/CONNECTED')
    end

    it 'keeps sending when the number quality is UNKNOWN' do
      set_health('UNKNOWN')

      expect(service.check_health!).to be(false)
    end
  end

  it 'clears the reason when the campaign is resumed' do
    service.check_error!(131_048)
    campaign.reload.resume!

    expect(campaign.reload.pause_reason).to be_nil
    expect(campaign).to be_processing
  end
end
