require 'rails_helper'

describe V2::Reports::LeadsTimelineMetrics do
  describe '#build' do
    it 'buckets leads by day and includes empty days as 0' do
      range = Time.zone.parse('2026-08-03T00:00:00Z')...Time.zone.parse('2026-08-06T00:00:00Z')
      leads = [
        { 'Created_Time' => '2026-08-03T10:00:00-06:00' },
        { 'Created_Time' => '2026-08-03T14:00:00-06:00' },
        { 'Created_Time' => '2026-08-05T09:00:00-06:00' }
      ]

      result = described_class.new(leads: leads, range: range, granularity: 'day').build

      expect(result[:granularity]).to eq('day')
      expect(result[:labels]).to eq(%w[03/08 04/08 05/08])
      expect(result[:counts]).to eq([2, 0, 1])
      expect(result[:dates]).to eq(%w[2026-08-03 2026-08-04 2026-08-05])
    end

    it 'buckets leads by week (Monday-start) when granularity is week' do
      range = Time.zone.parse('2026-08-03T00:00:00Z')...Time.zone.parse('2026-08-15T00:00:00Z')
      leads = [
        { 'Created_Time' => '2026-08-03T10:00:00-06:00' }, # lunes semana del 3
        { 'Created_Time' => '2026-08-05T10:00:00-06:00' }, # miércoles misma semana
        { 'Created_Time' => '2026-08-11T10:00:00-06:00' }  # semana del 10
      ]

      result = described_class.new(leads: leads, range: range, granularity: 'week').build

      expect(result[:counts]).to eq([2, 1])
      expect(result[:labels]).to eq(['Sem. 03/08', 'Sem. 10/08'])
    end

    it 'buckets leads by month with Spanish month labels' do
      range = Time.zone.parse('2026-07-01T00:00:00Z')...Time.zone.parse('2026-09-30T23:59:59Z')
      leads = [
        { 'Created_Time' => '2026-07-15T10:00:00-06:00' },
        { 'Created_Time' => '2026-09-02T10:00:00-06:00' }
      ]

      result = described_class.new(leads: leads, range: range, granularity: 'month').build

      expect(result[:labels]).to eq(['jul 2026', 'ago 2026', 'sep 2026'])
      expect(result[:counts]).to eq([1, 0, 1])
    end

    it 'ignores leads with a blank or unparseable Created_Time instead of raising' do
      range = Time.zone.parse('2026-08-03T00:00:00Z')...Time.zone.parse('2026-08-04T00:00:00Z')
      leads = [{ 'Created_Time' => nil }, { 'Created_Time' => 'not-a-date' }, { 'Created_Time' => '2026-08-03T10:00:00-06:00' }]

      result = described_class.new(leads: leads, range: range, granularity: 'day').build

      expect(result[:counts].sum).to eq(1)
    end

    it 'returns empty labels/counts when the range is blank' do
      result = described_class.new(leads: [], range: nil, granularity: 'day').build

      expect(result[:labels]).to eq([])
      expect(result[:counts]).to eq([])
    end

    it "buckets by the account's reporting_timezone instead of UTC when given" do
      account = create(:account, reporting_timezone: 'America/Mexico_City')
      range = Time.zone.parse('2026-08-03T00:00:00Z')...Time.zone.parse('2026-08-05T00:00:00Z')
      # 2026-08-03T23:30 en America/Mexico_City (UTC-6) es 2026-08-04T05:30 en UTC.
      leads = [{ 'Created_Time' => '2026-08-04T05:30:00Z' }]

      result = described_class.new(leads: leads, range: range, granularity: 'day', account: account).build

      expect(result[:labels]).to eq(%w[03/08 04/08])
      expect(result[:counts]).to eq([1, 0])
    end
  end
end
