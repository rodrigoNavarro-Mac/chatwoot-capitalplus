require 'rails_helper'

RSpec.describe QuoteDevelopmentRule do
  let(:account) { create(:account) }

  describe 'validations' do
    it 'requires at least one tier or a default interest' do
      rule = build(:quote_development_rule, account: account, quote_development_rule_tiers_attributes: [])

      expect(rule).to be_invalid
      expect(rule.errors[:base]).to include('debe tener al menos un tramo o un interés por defecto')
    end

    it 'allows a rule with only a default interest and no tiers' do
      rule = build(:quote_development_rule, account: account, interes_default: 12, quote_development_rule_tiers_attributes: [])

      expect(rule).to be_valid
    end

    it 'rejects a default interest out of range' do
      expect(build(:quote_development_rule, account: account, interes_default: -1)).to be_invalid
      expect(build(:quote_development_rule, account: account, interes_default: 100)).to be_invalid
    end

    it 'rejects more than one open-ended (hasta_meses: nil) tier' do
      rule = build(:quote_development_rule, account: account, quote_development_rule_tiers_attributes: [
                     { hasta_meses: nil, msi: false, requires_authorization: false },
                     { hasta_meses: nil, msi: false, requires_authorization: true }
                   ])

      expect(rule).to be_invalid
      expect(rule.errors[:base]).to include('solo puede haber un tramo sin límite superior de meses')
    end

    it 'rejects duplicate hasta_meses among tiers' do
      rule = build(:quote_development_rule, account: account, quote_development_rule_tiers_attributes: [
                     { hasta_meses: 12, msi: true, requires_authorization: false },
                     { hasta_meses: 12, msi: false, requires_authorization: true }
                   ])

      expect(rule).to be_invalid
      expect(rule.errors[:base]).to include('los límites de meses de los tramos deben ser únicos')
    end

    it 'enforces desarrollo uniqueness scoped to the account' do
      create(:quote_development_rule, account: account, desarrollo: 'Fuego')
      duplicate = build(:quote_development_rule, account: account, desarrollo: 'Fuego')

      expect(duplicate).to be_invalid
    end
  end

  describe '.default_interes_for' do
    it 'returns the rate configured for the development' do
      create(:quote_development_rule, account: account, desarrollo: 'Fuego', interes_default: 12)

      expect(described_class.default_interes_for(account, 'Fuego')).to eq(12)
    end

    it 'falls back to 8% without a rule or without a configured rate' do
      create(:quote_development_rule, account: account, desarrollo: 'Agua')

      expect(described_class.default_interes_for(account, 'Agua')).to eq(8)
      expect(described_class.default_interes_for(account, 'Tierra')).to eq(8)
      expect(described_class.default_interes_for(account, nil)).to eq(8)
    end

    it 'does not leak rates across accounts' do
      create(:quote_development_rule, account: create(:account), desarrollo: 'Fuego', interes_default: 12)

      expect(described_class.default_interes_for(account, 'Fuego')).to eq(8)
    end
  end

  describe '#tier_for' do
    let(:rule) do
      create(:quote_development_rule, account: account, quote_development_rule_tiers_attributes: [
               { hasta_meses: 12, msi: true, requires_authorization: false },
               { hasta_meses: 24, msi: true, requires_authorization: true },
               { hasta_meses: nil, msi: false, requires_authorization: true }
             ])
    end

    it 'returns the smallest tier that covers the given plazos' do
      expect(rule.tier_for(6)).to have_attributes(hasta_meses: 12)
      expect(rule.tier_for(12)).to have_attributes(hasta_meses: 12)
      expect(rule.tier_for(13)).to have_attributes(hasta_meses: 24)
      expect(rule.tier_for(24)).to have_attributes(hasta_meses: 24)
    end

    it 'falls back to the open-ended tier beyond every bounded tier' do
      expect(rule.tier_for(25)).to have_attributes(hasta_meses: nil)
      expect(rule.tier_for(1000)).to have_attributes(hasta_meses: nil)
    end
  end
end
