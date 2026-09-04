require 'rails_helper'

describe RevenueIntelligence::BudgetParser do
  describe '.parse' do
    it 'returns nil/nil for blank input' do
      expect(described_class.parse(nil)).to eq(min: nil, max: nil)
      expect(described_class.parse('')).to eq(min: nil, max: nil)
    end

    it 'returns nil/nil when there is no recognizable number' do
      expect(described_class.parse('por definir')).to eq(min: nil, max: nil)
      expect(described_class.parse('no tiene')).to eq(min: nil, max: nil)
    end

    it 'treats a single plain number as a point estimate (min == max)' do
      expect(described_class.parse('1500000')).to eq(min: 1_500_000.0, max: 1_500_000.0)
    end

    it 'applies the "millones" multiplier' do
      expect(described_class.parse('1.5 millones')).to eq(min: 1_500_000.0, max: 1_500_000.0)
    end

    it 'applies the "mdp" multiplier' do
      expect(described_class.parse('2 mdp')).to eq(min: 2_000_000.0, max: 2_000_000.0)
    end

    it 'applies the "mil" multiplier' do
      expect(described_class.parse('800 mil')).to eq(min: 800_000.0, max: 800_000.0)
    end

    it 'strips thousands-separator commas and the $ sign' do
      expect(described_class.parse('$1,200,000')).to eq(min: 1_200_000.0, max: 1_200_000.0)
    end

    it 'parses a range with two numbers, min as the smaller and max as the larger regardless of order' do
      expect(described_class.parse('800 mil - 1.2 millones')).to eq(min: 800_000.0, max: 1_200_000.0)
    end

    it 'sets only max when qualified with "hasta"' do
      expect(described_class.parse('hasta 2 millones')).to eq(min: nil, max: 2_000_000.0)
    end

    it 'sets only min when qualified with "desde"' do
      expect(described_class.parse('desde 900 mil')).to eq(min: 900_000.0, max: nil)
    end
  end
end
