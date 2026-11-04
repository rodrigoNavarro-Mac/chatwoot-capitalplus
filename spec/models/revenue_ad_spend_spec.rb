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

  # Fase 22 §3/§4: integridad del historial de revisiones -- append-only, solo ante cambio
  # efectivo, nunca retrocede observed_at artificialmente.
  describe '#record_revision_if_changed!' do
    let(:spend) { build_spend(amount: 1000).tap(&:save!) }

    it 'creates no revision for a brand-new record (no previous value to compare against)' do
      brand_new = build_spend(campaign_name: 'Camp New')
      brand_new.record_revision_if_changed!(500, observed_at: Time.current) unless brand_new.new_record?

      expect(brand_new.revisions).to be_empty
    end

    it 'does not create a revision when the amount is unchanged (idempotencia ante re-sincronizaciones sin cambio)' do
      expect do
        spend.record_revision_if_changed!(1000, observed_at: Time.current)
      end.not_to change(spend.revisions, :count)
    end

    it 'creates exactly one revision when the amount changes' do
      expect do
        spend.record_revision_if_changed!(1250.50, observed_at: Time.current)
      end.to change(spend.revisions, :count).by(1)
      expect(spend.revisions.last.amount).to eq(1250.50)
    end

    it 'accumulates one revision per distinct change across multiple syncs, preserving full history' do
      spend.record_revision_if_changed!(1100, observed_at: 2.days.ago)
      spend.record_revision_if_changed!(1100, observed_at: 1.day.ago) # sin cambio, no debe duplicar
      spend.record_revision_if_changed!(1200, observed_at: Time.current)

      expect(spend.revisions.order(:observed_at).pluck(:amount)).to eq([BigDecimal('1100.0'), BigDecimal('1200.0')])
    end

    it 'rejects a revision with an observed_at in the future (protección contra backdating/forward-dating artificial)' do
      spend.record_revision_if_changed!(1100, observed_at: Time.current)
      expect { spend.record_revision_if_changed!(1300, observed_at: 1.year.from_now) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'destroys revisions when the parent spend row is destroyed (no orphaned history)' do
      spend.record_revision_if_changed!(1100, observed_at: Time.current)
      revision_id = spend.revisions.sole.id

      spend.destroy!

      expect(RevenueAdSpendRevision.find_by(id: revision_id)).to be_nil
    end
  end

  # Fase 22 §3/§4: consultas point-in-time SIN fuga -- nunca debe devolver un valor que todavía
  # no se conocía en el instante consultado, por más cercano que esté en el tiempo.
  describe '.known_amount_as_of' do
    let(:spend) { build_spend(amount: 1000).tap(&:save!) }

    it 'returns the amount known at or before the given instant, never a later revision' do
      spend.record_revision_if_changed!(1100, observed_at: 10.days.ago)
      spend.record_revision_if_changed!(1300, observed_at: 1.day.ago)

      expect(RevenueAdSpendRevision.known_amount_as_of(spend.id, 5.days.ago)).to eq(BigDecimal('1100.0'))
    end

    it 'returns nil when nothing was known yet at that instant (no sustituye por el valor actual)' do
      spend.record_revision_if_changed!(1100, observed_at: 1.day.ago)

      expect(RevenueAdSpendRevision.known_amount_as_of(spend.id, 10.days.ago)).to be_nil
    end

    it 'never leaks a revision observed strictly after the reference instant, even by seconds' do
      reference = Time.zone.parse('2026-10-15 12:00:00')
      spend.record_revision_if_changed!(1100, observed_at: reference - 1.second)
      spend.record_revision_if_changed!(9999, observed_at: reference + 1.second)

      expect(RevenueAdSpendRevision.known_amount_as_of(spend.id, reference)).to eq(BigDecimal('1100.0'))
    end
  end
end
