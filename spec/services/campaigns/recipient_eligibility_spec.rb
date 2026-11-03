require 'rails_helper'

RSpec.describe Campaigns::RecipientEligibility do
  subject(:eligibility) { described_class.new(campaign: campaign) }

  let(:account) { create(:account) }
  let!(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:campaign) { create(:campaign, inbox: whatsapp_channel.inbox, account: account) }
  let(:other_campaign) { create(:campaign, inbox: whatsapp_channel.inbox, account: account) }
  let(:opt_out_key) { format(Redis::RedisKeys::WA_OPTED_OUT_PHONES, account_id: account.id) }

  after { Redis::Alfred.delete(opt_out_key) }

  def create_delivery(target_campaign, phone, sent_at:, source_id: SecureRandom.hex(8))
    target_campaign.campaign_message_deliveries.create!(
      account_id: account.id, audience_type: 'csv', phone_number: phone, source_id: source_id, status: 'sent', sent_at: sent_at
    )
  end

  it 'allows a phone with no history' do
    expect(eligibility.eligible?('+525511112222')).to be(true)
  end

  it 'blocks an opted-out phone, matching the 52/521 variants by their last 10 digits' do
    described_class.opt_out!(account.id, '+5215511112222')

    expect(eligibility.eligible?('+525511112222')).to be(false)
    expect(eligibility.blocked_keys).to include('5511112222')
  end

  it 'blocks a phone that got another campaign within 14 days' do
    create_delivery(other_campaign, '+5215511112222', sent_at: 5.days.ago)

    expect(eligibility.eligible?('+525511112222')).to be(false)
    expect(eligibility.blocked_keys).to include('5511112222')
  end

  it 'allows a phone whose last campaign was more than 14 days ago' do
    create_delivery(other_campaign, '+525511112222', sent_at: 15.days.ago)

    expect(eligibility.eligible?('+525511112222')).to be(true)
  end

  it 'ignores deliveries of the same campaign and attempts that never reached Meta' do
    create_delivery(campaign, '+525511112222', sent_at: 1.day.ago)
    create_delivery(other_campaign, '+525533334444', sent_at: 1.day.ago, source_id: nil)

    expect(eligibility.eligible?('+525511112222')).to be(true)
    expect(eligibility.eligible?('+525533334444')).to be(true)
  end

  describe '.opt_out_message?' do
    it 'detects opt-out replies' do
      expect(described_class.opt_out_message?('BAJA')).to be(true)
      expect(described_class.opt_out_message?('Ya no, no me interesa gracias')).to be(true)
      expect(described_class.opt_out_message?('Me interesa, precio?')).to be(false)
    end
  end
end
