require 'rails_helper'

describe RevenueAdCreativeSnapshot do
  let(:account) { create(:account) }

  def build_snapshot(**attrs)
    account.revenue_ad_creative_snapshots.new({ meta_ad_id: 'ad-1', format: 'image', fetched_at: Time.current }.merge(attrs))
  end

  describe 'validations' do
    it 'requires meta_ad_id' do
      expect(build_snapshot(meta_ad_id: nil)).to be_invalid
    end

    it 'requires fetched_at' do
      expect(build_snapshot(fetched_at: nil)).to be_invalid
    end

    it 'only accepts formats from the allow-list' do
      expect(build_snapshot(format: 'image')).to be_valid
      expect(build_snapshot(format: 'algo_no_permitido')).to be_invalid
    end

    it 'allows a nil format (creativo sin formato confirmado todavía)' do
      expect(build_snapshot(format: nil)).to be_valid
    end

    it 'allows multiple snapshots for the same meta_ad_id (versionado, sin unique index)' do
      build_snapshot.save!
      expect(build_snapshot).to be_valid
    end
  end

  # Fase 22 §3: solo la lista permitida de campos se persiste -- nunca una respuesta cruda.
  it 'exposes only the allow-listed creative fields as columns, never a raw payload' do
    expect(described_class.column_names).to include('format', 'media_type', 'title', 'body', 'call_to_action_type', 'creative_id')
    expect(described_class.column_names).not_to include('raw_payload')
  end

  describe '.as_of (consulta point-in-time)' do
    it 'returns the most recent snapshot at or before the given date, never a later one' do
      older = build_snapshot(title: 'Versión original', fetched_at: 10.days.ago).tap(&:save!)
      newer = build_snapshot(title: 'Versión editada', fetched_at: 1.day.ago).tap(&:save!)

      expect(described_class.as_of('ad-1', 5.days.ago)).to eq(older)
      expect(described_class.as_of('ad-1', Time.current)).to eq(newer)
    end

    it 'returns nil when there is no snapshot at or before that date (nunca usa una versión futura)' do
      build_snapshot(fetched_at: 1.day.from_now).save!

      expect(described_class.as_of('ad-1', Time.current)).to be_nil
    end

    it 'scopes strictly by meta_ad_id, never leaking a snapshot from a different ad' do
      build_snapshot(meta_ad_id: 'ad-other', title: 'De otro anuncio', fetched_at: 1.day.ago).save!

      expect(described_class.as_of('ad-1', Time.current)).to be_nil
    end
  end
end
