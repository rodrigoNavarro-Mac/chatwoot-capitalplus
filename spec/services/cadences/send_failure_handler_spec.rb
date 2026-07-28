require 'rails_helper'

describe Cadences::SendFailureHandler do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, assignee: agent, status: 'open')
  end
  let(:cadence_definition) { create_cadence_definition!(whatsapp_inbox) }
  let(:enrollment) do
    CadenceEnrollment.create!(
      account: account, conversation: conversation, contact: contact, inbox: whatsapp_inbox,
      cadence_definition: cadence_definition, assignee_id: agent.id,
      status: :active, steps_snapshot: cadence_steps_snapshot(count: 3)
    )
  end

  before { account.enable_features!(:whatsapp_cadences) }

  context 'when the error is not transient' do
    it 'terminates the enrollment immediately' do
      described_class.new(enrollment: enrollment, error_detail: 'Template not approved', error_code: 132_000).call

      enrollment.reload
      expect(enrollment.status).to eq('failed')
      expect(enrollment.stopped_reason).to eq('send_failed: Template not approved')
      expect(enrollment.send_retry_count).to eq(0)
    end

    it 'terminates immediately when transient is explicitly false' do
      described_class.new(enrollment: enrollment, error_detail: 'boom', transient: false).call

      expect(enrollment.reload.status).to eq('failed')
    end
  end

  context 'when the error is transient (media upload error)' do
    it 'schedules a retry with the first backoff instead of terminating' do
      travel_to(Time.zone.local(2026, 1, 1, 12, 0, 0)) do
        described_class.new(enrollment: enrollment, error_detail: 'Media upload error', error_code: 131_053).call

        enrollment.reload
        expect(enrollment.status).to eq('active')
        expect(enrollment.send_retry_count).to eq(1)
        expect(enrollment.next_action_at).to eq(2.minutes.from_now)
      end
    end

    it 'enqueues AdvanceJob for the scheduled retry time' do
      expect { described_class.new(enrollment: enrollment, error_detail: 'x', error_code: 131_053).call }
        .to have_enqueued_job(Cadences::AdvanceJob).with(enrollment.id)
    end

    it 'logs a send_retry_scheduled event' do
      described_class.new(enrollment: enrollment, error_detail: 'x', error_code: 131_053).call

      expect(enrollment.cadence_events.pluck(:event_type)).to include('send_retry_scheduled')
    end

    it 'is also transient for a Meta rate-limit error' do
      described_class.new(enrollment: enrollment, error_detail: 'x', error_code: 130_429).call

      expect(enrollment.reload.status).to eq('active')
    end

    it 'is also transient when the caller explicitly marks it as such (network timeouts)' do
      described_class.new(enrollment: enrollment, error_detail: 'Net::ReadTimeout', transient: true).call

      expect(enrollment.reload.status).to eq('active')
    end

    it 'increases the backoff on each subsequent attempt' do
      enrollment.update!(send_retry_count: 1)

      travel_to(Time.zone.local(2026, 1, 1, 12, 0, 0)) do
        described_class.new(enrollment: enrollment, error_detail: 'x', error_code: 131_053).call

        enrollment.reload
        expect(enrollment.send_retry_count).to eq(2)
        expect(enrollment.next_action_at).to eq(5.minutes.from_now)
      end
    end

    it 'terminates permanently after exhausting the max retries' do
      enrollment.update!(send_retry_count: described_class::MAX_RETRIES)

      described_class.new(enrollment: enrollment, error_detail: 'still failing', error_code: 131_053).call

      enrollment.reload
      expect(enrollment.status).to eq('failed')
      expect(enrollment.stopped_reason).to eq('send_failed_max_retries: still failing')
    end
  end
end
