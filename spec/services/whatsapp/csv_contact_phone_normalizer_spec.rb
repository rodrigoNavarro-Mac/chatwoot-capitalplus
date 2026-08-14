require 'rails_helper'

describe Whatsapp::CsvContactPhoneNormalizer do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp_channel.inbox }
  let(:normalizer) { described_class.new(inbox: inbox) }

  it 'strips the legacy Mexican mobile "1" prefix and keeps the leading +' do
    expect(normalizer.normalize('+5215569440704')).to eq('+525569440704')
  end

  it 'returns the number unchanged (with +) when no country normalizer applies' do
    expect(normalizer.normalize('+12025550123')).to eq('+12025550123')
  end
end
