require 'rails_helper'

describe Whatsapp::PhoneNumberNormalizationService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp_channel.inbox }
  let(:service) { described_class.new(inbox) }

  describe '#normalize' do
    it 'strips the legacy "1" mobile prefix from a Mexican number for the :cloud provider' do
      expect(service.normalize('5215569440704', :cloud)).to eq('525569440704')
    end

    it 'formats a normalized number for the :twilio provider' do
      expect(service.normalize('whatsapp:+5215569440704', :twilio)).to eq('whatsapp:+525569440704')
    end

    it 'returns the raw number unchanged when no country normalizer applies' do
      expect(service.normalize('12025550123', :cloud)).to eq('12025550123')
    end
  end

  describe '#normalize_and_find_contact_by_provider' do
    it 'returns the existing contact_inbox source_id when one exists under the normalized number' do
      contact_inbox = create(:contact_inbox, inbox: inbox, source_id: '525569440704')

      expect(service.normalize_and_find_contact_by_provider('5215569440704', :cloud)).to eq(contact_inbox.source_id)
    end

    it 'returns the raw number when no contact_inbox exists under the normalized number' do
      expect(service.normalize_and_find_contact_by_provider('5215569440704', :cloud)).to eq('5215569440704')
    end
  end
end
