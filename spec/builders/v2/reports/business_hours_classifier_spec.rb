require 'rails_helper'

describe V2::Reports::BusinessHoursClassifier do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp_channel.inbox }

  describe '#within_business_hours?' do
    it 'returns true for a time within the configured range on that day of week' do
      # 2026-08-03 es lunes (day_of_week: 1).
      create(:working_hour, inbox: inbox, day_of_week: 1, open_hour: 9, open_minutes: 0, close_hour: 17, close_minutes: 0)

      time = Time.zone.parse('2026-08-03T12:00:00Z')

      expect(described_class.new(inbox).within_business_hours?(time)).to be true
    end

    it 'returns false for a time outside the configured range on that day of week' do
      create(:working_hour, inbox: inbox, day_of_week: 1, open_hour: 9, open_minutes: 0, close_hour: 17, close_minutes: 0)

      time = Time.zone.parse('2026-08-03T20:00:00Z')

      expect(described_class.new(inbox).within_business_hours?(time)).to be false
    end

    it 'returns false when the day is marked closed_all_day' do
      create(:working_hour, inbox: inbox, day_of_week: 1, closed_all_day: true, open_hour: nil, open_minutes: nil, close_hour: nil,
                            close_minutes: nil)

      time = Time.zone.parse('2026-08-03T12:00:00Z')

      expect(described_class.new(inbox).within_business_hours?(time)).to be false
    end

    it 'returns true any time of day when marked open_all_day' do
      create(:working_hour, inbox: inbox, day_of_week: 1, open_all_day: true)

      time = Time.zone.parse('2026-08-03T23:30:00Z')

      expect(described_class.new(inbox).within_business_hours?(time)).to be true
    end

    it 'returns false when there is no WorkingHour configured for that day of week' do
      # El inbox ya trae los 7 días por default (after_create :create_default_working_hours en
      # OutOfOffisable) — se destruyen para probar genuinamente el caso "sin configurar".
      inbox.working_hours.destroy_all
      create(:working_hour, inbox: inbox, day_of_week: 2, open_hour: 9, open_minutes: 0, close_hour: 17, close_minutes: 0)

      time = Time.zone.parse('2026-08-03T12:00:00Z') # lunes, no hay working_hour para el 1

      expect(described_class.new(inbox).within_business_hours?(time)).to be false
    end

    it 'resolves the day of week and time of day in the inbox timezone, not UTC' do
      inbox.update!(timezone: 'America/Mexico_City')
      # 2026-08-03T23:30 en America/Mexico_City (UTC-6) es 2026-08-04T05:30 en UTC — el día real,
      # en la zona del inbox, sigue siendo lunes (day_of_week 1), no martes.
      create(:working_hour, inbox: inbox, day_of_week: 1, open_hour: 9, open_minutes: 0, close_hour: 23, close_minutes: 59)

      time = Time.zone.parse('2026-08-04T05:30:00Z')

      expect(described_class.new(inbox).within_business_hours?(time)).to be true
    end

    it 'returns false for a blank time instead of raising' do
      create(:working_hour, inbox: inbox, day_of_week: 1)

      expect(described_class.new(inbox).within_business_hours?(nil)).to be false
    end
  end
end
