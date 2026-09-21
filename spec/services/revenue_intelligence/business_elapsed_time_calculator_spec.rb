require 'rails_helper'

describe RevenueIntelligence::BusinessElapsedTimeCalculator do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  # El inbox ya trae Lun-Vie 09:00-17:00 / Sáb-Dom cerrado por default (after_create en
  # OutOfOffisable::DEFAULT_WORKING_HOURS) -- no hace falta crear WorkingHour a mano para el caso
  # típico, solo fijar el timezone para que las fechas locales del test sean inequívocas.
  let(:inbox) { whatsapp_channel.inbox.tap { |i| i.update!(timezone: 'America/Mexico_City') } }
  let(:zone) { ActiveSupport::TimeZone['America/Mexico_City'] }

  describe '#elapsed_seconds' do
    it 'does not start counting until the next shift when the lead arrives outside business hours ' \
       '(created 1am, shift starts 9am, contacted 9:04am -> 4 minutes, not 8h4m)' do
      # 2026-08-03 es lunes.
      created_at = zone.local(2026, 8, 3, 1, 0, 0)
      contacted_at = zone.local(2026, 8, 3, 9, 4, 0)

      elapsed = described_class.new(inbox).elapsed_seconds(created_at, contacted_at)

      expect(elapsed).to eq(4.minutes)
    end

    it 'counts wall-clock time directly when the lead arrives during business hours' do
      created_at = zone.local(2026, 8, 3, 10, 2, 0)
      contacted_at = zone.local(2026, 8, 3, 10, 7, 0)

      elapsed = described_class.new(inbox).elapsed_seconds(created_at, contacted_at)

      expect(elapsed).to eq(5.minutes)
    end

    it 'skips entire closed days (weekend) without counting any of their wall-clock time' do
      # 2026-07-31 es viernes, 2026-08-03 es el lunes siguiente.
      created_at = zone.local(2026, 7, 31, 16, 0, 0) # 1h antes del cierre del viernes
      contacted_at = zone.local(2026, 8, 3, 9, 30, 0) # 30 min después de abrir el lunes

      elapsed = described_class.new(inbox).elapsed_seconds(created_at, contacted_at)

      expect(elapsed).to eq(90.minutes) # 1h viernes + 30min lunes, cero fin de semana
    end

    it 'returns 0 when the lead is created and contacted entirely within a closed day' do
      created_at = zone.local(2026, 8, 1, 10, 0, 0) # sábado, cerrado
      contacted_at = zone.local(2026, 8, 1, 14, 0, 0)

      expect(described_class.new(inbox).elapsed_seconds(created_at, contacted_at)).to eq(0)
    end

    it 'returns 0 for a blank start or end time instead of raising' do
      calculator = described_class.new(inbox)

      expect(calculator.elapsed_seconds(nil, Time.current)).to eq(0)
      expect(calculator.elapsed_seconds(Time.current, nil)).to eq(0)
    end

    it 'returns 0 when end_time is before start_time' do
      start_time = zone.local(2026, 8, 3, 10, 0, 0)
      end_time = zone.local(2026, 8, 3, 9, 0, 0)

      expect(described_class.new(inbox).elapsed_seconds(start_time, end_time)).to eq(0)
    end
  end
end
