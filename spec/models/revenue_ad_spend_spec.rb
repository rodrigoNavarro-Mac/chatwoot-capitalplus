require 'rails_helper'

describe RevenueAdSpend do
  let(:account) { create(:account) }

  def build_spend(**attrs)
    account.revenue_ad_spends.new({ campaign_name: 'Camp X', period_start: 10.days.ago.to_date, period_end: 1.day.ago.to_date,
                                    amount: 1000 }.merge(attrs))
  end

  describe 'validations' do
    it 'is valid with only campaign-level attribution (adset_name/advert_name nil)' do
      expect(build_spend).to be_valid
    end

    it 'requires campaign_name' do
      expect(build_spend(campaign_name: nil)).to be_invalid
    end

    it 'requires amount to be >= 0' do
      expect(build_spend(amount: -1)).to be_invalid
      expect(build_spend(amount: 0)).to be_valid
    end

    it 'requires period_start to be on or before period_end' do
      spend = build_spend(period_start: Date.current, period_end: 10.days.ago.to_date)
      expect(spend).to be_invalid
      expect(spend.errors[:period_end]).to be_present
    end

    it 'only accepts MXN as currency' do
      expect(build_spend(currency: 'USD')).to be_invalid
      expect(build_spend(currency: 'MXN')).to be_valid
    end

    it 'defaults source to manual and only accepts manual/meta_api' do
      expect(build_spend.source).to eq('manual')
      expect(build_spend(source: 'meta_api')).to be_valid
      expect(build_spend(source: 'zoho')).to be_invalid
    end

    it 'rejects an exact duplicate (same campaign/adset/advert/period), even when adset/advert are both nil' do
      build_spend.save!

      expect(build_spend).to be_invalid
    end

    it 'allows the same campaign+period at a different ad level (adset/advert present) as a separate row' do
      build_spend.save!

      expect(build_spend(adset_name: 'Adset 1')).to be_valid
    end

    it 'allows a different period for the same campaign/adset/advert' do
      build_spend.save!

      expect(build_spend(period_start: 20.days.ago.to_date, period_end: 11.days.ago.to_date)).to be_valid
    end
  end

  describe '#overlapping' do
    it 'finds an existing record whose period overlaps the same campaign/adset/advert' do
      existing = build_spend(period_start: 10.days.ago.to_date, period_end: 1.day.ago.to_date)
      existing.save!

      overlapping = build_spend(period_start: 5.days.ago.to_date, period_end: Date.current)

      expect(overlapping.overlapping).to include(existing)
    end

    it 'does not consider itself an overlap when already persisted' do
      existing = build_spend
      existing.save!

      expect(existing.overlapping).to be_empty
    end

    it 'does not flag two non-overlapping periods for the same ad' do
      build_spend(period_start: 30.days.ago.to_date, period_end: 20.days.ago.to_date).save!

      later = build_spend(period_start: 10.days.ago.to_date, period_end: 1.day.ago.to_date)

      expect(later.overlapping).to be_empty
    end

    it 'never matches a different campaign/adset/advert, even with the exact same period' do
      build_spend(campaign_name: 'Camp Y', period_start: 10.days.ago.to_date, period_end: 1.day.ago.to_date).save!

      same_period_other_campaign = build_spend(period_start: 10.days.ago.to_date, period_end: 1.day.ago.to_date)

      expect(same_period_other_campaign.overlapping).to be_empty
    end
  end

  describe '.within_period' do
    it 'only returns records fully contained within the given range, never a partial/prorated match' do
      contained = build_spend(period_start: 15.days.ago.to_date, period_end: 5.days.ago.to_date)
      contained.save!
      partial = build_spend(campaign_name: 'Camp Y', period_start: 25.days.ago.to_date, period_end: 5.days.ago.to_date)
      partial.save!

      result = account.revenue_ad_spends.within_period(20.days.ago.to_date, Date.current)

      expect(result).to contain_exactly(contained)
    end
  end

  describe '.manual / .meta_api scopes' do
    it 'splits records by source' do
      manual = build_spend.tap(&:save!)
      auto = build_spend(campaign_name: 'Camp Y', source: 'meta_api').tap(&:save!)

      expect(account.revenue_ad_spends.manual).to contain_exactly(manual)
      expect(account.revenue_ad_spends.meta_api).to contain_exactly(auto)
    end
  end
end
