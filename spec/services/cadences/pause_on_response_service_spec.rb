require 'rails_helper'

describe Cadences::PauseOnResponseService do
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
      status: :waiting_response, current_step: 2, last_template_sent_at: 1.hour.ago,
      steps_snapshot: cadence_steps_snapshot(count: 6)
    )
  end
  let(:incoming_message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }

  describe '#perform' do
    it 'pauses the cadence and records the response' do
      described_class.new(enrollment: enrollment, message: incoming_message).perform

      enrollment.reload
      expect(enrollment.status).to eq('paused_by_response')
      expect(enrollment.last_lead_response_at).to be_present
      expect(enrollment.cadence_events.pluck(:event_type)).to include('lead_replied', 'cadence_paused')
    end

    it 'marks the enrollment as recovered when the response comes after the last (recovery) step' do
      enrollment.update!(current_step: 6)

      described_class.new(enrollment: enrollment, message: incoming_message).perform

      expect(enrollment.reload.status).to eq('recovered')
      expect(enrollment.cadence_events.pluck(:event_type)).to include('cadence_recovered')
    end

    it 'derives "last step" from the enrollment steps_snapshot, not a hardcoded step number' do
      enrollment.update!(current_step: 3, steps_snapshot: cadence_steps_snapshot(count: 3))

      described_class.new(enrollment: enrollment, message: incoming_message).perform

      expect(enrollment.reload.status).to eq('recovered')
    end

    it 'skips pending call tasks' do
      task = CadenceCallTask.create!(account: account, cadence_enrollment: enrollment, conversation: conversation, user: agent, step: 2,
                                     status: :pending)

      described_class.new(enrollment: enrollment, message: incoming_message).perform

      expect(task.reload.status).to eq('skipped')
    end

    it 'does nothing when the cadence already finished' do
      enrollment.update!(status: :completed)

      expect { described_class.new(enrollment: enrollment, message: incoming_message).perform }
        .not_to(change { enrollment.reload.status })
    end
  end
end
