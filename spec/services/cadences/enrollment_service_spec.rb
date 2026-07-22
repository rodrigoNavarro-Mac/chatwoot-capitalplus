require 'rails_helper'

describe Cadences::EnrollmentService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, assignee: agent, status: 'open')
  end

  before do
    account.enable_features!(:whatsapp_cadences)
    create_cadence_steps!(whatsapp_inbox)
  end

  describe '#enroll!' do
    it 'creates an active enrollment at step 0 and logs cadence_started' do
      expect { described_class.new(conversation: conversation).enroll! }.to change(CadenceEnrollment, :count).by(1)

      enrollment = CadenceEnrollment.last
      expect(enrollment.status).to eq('active')
      expect(enrollment.current_step).to eq(0)
      expect(enrollment.conversation_id).to eq(conversation.id)
      expect(enrollment.contact_id).to eq(contact.id)
      expect(enrollment.assignee_id).to eq(agent.id)
      expect(enrollment.cadence_events.pluck(:event_type)).to include('cadence_started')
    end

    it 'stamps steps_snapshot with the inbox current step definitions' do
      described_class.new(conversation: conversation).enroll!

      enrollment = CadenceEnrollment.last
      expect(enrollment.total_steps).to eq(3)
      expect(enrollment.step_definition_for(1)[:schedule_type]).to eq('immediate')
    end

    it 'does not enroll when the inbox has no cadence steps configured' do
      whatsapp_inbox.cadence_definitions.each { |definition| definition.cadence_step_definitions.delete_all }

      expect { described_class.new(conversation: conversation).enroll! }.not_to change(CadenceEnrollment, :count)
    end

    it 'does not enroll when the inbox has no cadence definitions at all (no default to fall back to)' do
      whatsapp_inbox.cadence_definitions.destroy_all

      expect { described_class.new(conversation: conversation).enroll! }.not_to change(CadenceEnrollment, :count)
    end

    it 'enqueues the first AdvanceJob' do
      expect { described_class.new(conversation: conversation).enroll! }
        .to have_enqueued_job(Cadences::AdvanceJob)
    end

    it 'does not enroll twice for the same conversation' do
      described_class.new(conversation: conversation).enroll!

      expect { described_class.new(conversation: conversation).enroll! }.not_to change(CadenceEnrollment, :count)
    end

    it 'does not enroll when the feature flag is disabled' do
      account.disable_features!(:whatsapp_cadences)

      expect { described_class.new(conversation: conversation).enroll! }.not_to change(CadenceEnrollment, :count)
    end

    it 'enrolls even when the conversation has no assignee' do
      conversation.update!(assignee_id: nil)

      expect { described_class.new(conversation: conversation).enroll! }.to change(CadenceEnrollment, :count).by(1)
      expect(CadenceEnrollment.last.assignee_id).to be_nil
    end

    it 'does not enroll a non-WhatsApp conversation' do
      other_inbox = create(:inbox, account: account, channel: create(:channel_widget, account: account))
      other_conversation = create(:conversation, account: account, inbox: other_inbox, contact: contact, assignee: agent)

      expect { described_class.new(conversation: other_conversation).enroll! }.not_to change(CadenceEnrollment, :count)
    end
  end
end
