require 'rails_helper'

describe RevenueIntelligence::MetaAdsDesarrolloResolver do
  describe '.resolve' do
    it 'matches Fuego campaigns case-insensitively' do
      expect(described_class.resolve('✅ Fuego 11 Abril (Refresh Creativos) - DC')).to eq('Fuego')
      expect(described_class.resolve('Campaña 7 Fuego - Asesores a Cámara + Carrusel')).to eq('Fuego')
    end

    it 'matches Amura campaigns regardless of casing (AMURA vs Amura)' do
      expect(described_class.resolve('🟢 AMURA Refresh Creativos 13 Mayo - Whatsapp Manual')).to eq('Amura')
      expect(described_class.resolve('✅ Amura - 5 ADS DC - Whatsapp Manual')).to eq('Amura')
    end

    it 'matches P. Quintana Roo campaigns by the "Quintana Roo" keyword (the full desarrollo name never appears verbatim)' do
      expect(described_class.resolve('CAMPAÑA Quintana Roo (Lomas) - Video voiceover')).to eq('P. Quintana Roo')
    end

    it 'returns nil for a desarrollo with no confirmed keyword yet, instead of guessing' do
      expect(described_class.resolve('Hazúl lanzamiento primavera')).to be_nil
      expect(described_class.resolve('M2 campaña nueva')).to be_nil
    end

    it 'returns nil for blank input' do
      expect(described_class.resolve(nil)).to be_nil
      expect(described_class.resolve('')).to be_nil
    end
  end
end
