require 'rails_helper'

describe Cadences::ScheduleCalculator do
  let(:account) { create(:account) }
  let(:enrolled_at) { Time.zone.local(2026, 7, 10, 5, 0, 0) }
  let(:last_template_sent_at) { Time.zone.local(2026, 7, 10, 5, 30, 0) }
  let(:cadence_definition) { create_cadence_definition!(whatsapp_inbox) }
  let(:enrollment) do
    CadenceEnrollment.create!(
      account: account, conversation: conversation, contact: contact, inbox: whatsapp_inbox,
      cadence_definition: cadence_definition, assignee_id: agent.id,
      created_at: enrolled_at, last_template_sent_at: last_template_sent_at
    )
  end
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, assignee: agent, status: 'open')
  end

  # "Ahora" se congela para que los anchors (fijados un poco antes) y sus offsets caigan
  # de forma predecible antes/después de "ahora" — si no, el guard "nunca en el pasado"
  # de next_run_at los recorta a Time.current y las aserciones dejan de reflejar el cálculo real.
  around { |example| travel_to(Time.zone.local(2026, 7, 10, 6, 0, 0)) { example.run } }

  describe '#next_run_at' do
    it 'returns the current time for an immediate schedule' do
      run_at = described_class.new(enrollment: enrollment, definition: { schedule_type: 'immediate' }).next_run_at

      expect(run_at).to be_within(1.second).of(Time.current)
    end

    it 'anchors offset_from_last_step on last_template_sent_at, not on the enrollment date' do
      definition = { schedule_type: 'offset_from_last_step', offset_minutes: 120 }

      run_at = described_class.new(enrollment: enrollment, definition: definition).next_run_at

      expect(run_at).to eq(last_template_sent_at + 120.minutes)
    end

    it 'anchors day_offset_at_time on the date of the last template sent, not the enrollment date' do
      definition = { schedule_type: 'day_offset_at_time', day_offset: 1, time_of_day: '09:00' }

      run_at = described_class.new(enrollment: enrollment, definition: definition).next_run_at

      expected_date = last_template_sent_at.in_time_zone('America/Mexico_City').to_date + 1
      expect(run_at).to eq(ActiveSupport::TimeZone['America/Mexico_City'].local(expected_date.year, expected_date.month, expected_date.day, 9, 0))
    end

    it 'falls back to enrollment.created_at when no template has been sent yet' do
      enrollment.update_column(:last_template_sent_at, nil) # rubocop:disable Rails/SkipsModelValidations
      definition = { schedule_type: 'offset_from_last_step', offset_minutes: 90 }

      run_at = described_class.new(enrollment: enrollment, definition: definition).next_run_at

      expect(run_at).to eq(enrolled_at + 90.minutes)
    end

    it 'never schedules in the past' do
      definition = { schedule_type: 'offset_from_last_step', offset_minutes: -1_000_000 }

      run_at = described_class.new(enrollment: enrollment, definition: definition).next_run_at

      expect(run_at).to be_within(1.second).of(Time.current)
    end
  end
end
