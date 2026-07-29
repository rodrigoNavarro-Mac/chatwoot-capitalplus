require 'rails_helper'

describe Whatsapp::PhoneNormalizers::MexicoPhoneNormalizer do
  subject(:normalizer) { described_class.new }

  describe '#handles_country?' do
    it 'handles numbers starting with the Mexico country code (52)' do
      expect(normalizer.handles_country?('5215512345678')).to be_present
    end

    it 'does not handle numbers from other countries' do
      expect(normalizer.handles_country?('5511987654321')).to be_nil
    end
  end

  describe '#normalize' do
    it 'strips the legacy mobile "1" prefix when present (13 digits)' do
      expect(normalizer.normalize('5215512345678')).to eq('525512345678')
    end

    it 'leaves the number unchanged when already in the 12-digit format' do
      expect(normalizer.normalize('525512345678')).to eq('525512345678')
    end

    it 'returns the number unchanged for a non-Mexico country code' do
      expect(normalizer.normalize('5511987654321')).to eq('5511987654321')
    end
  end
end
