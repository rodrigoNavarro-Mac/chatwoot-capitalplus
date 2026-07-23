require 'rails_helper'

describe Cadences::SendRateLimiter do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp_channel.inbox }

  describe '#claim_slot!' do
    it 'claims the slot the first time it is called for an inbox' do
      expect(described_class.new(inbox: inbox).claim_slot!).to be true
    end

    it 'refuses a second claim for the same inbox within the rate limit window' do
      described_class.new(inbox: inbox).claim_slot!

      expect(described_class.new(inbox: inbox).claim_slot!).to be false
    end

    it 'allows independent claims for different inboxes' do
      other_inbox = create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false).inbox

      described_class.new(inbox: inbox).claim_slot!

      expect(described_class.new(inbox: other_inbox).claim_slot!).to be true
    end
  end
end
