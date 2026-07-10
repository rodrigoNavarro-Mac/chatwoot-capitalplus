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

  before { account.enable_features!(:whatsapp_cadences) }

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

    it 'does not enroll when the conversation has no assignee' do
      conversation.update_column(:assignee_id, nil)

      expect { described_class.new(conversation: conversation).enroll! }.not_to change(CadenceEnrollment, :count)
    end

    it 'does not enroll a non-WhatsApp conversation' do
      other_inbox = create(:inbox, account: account, channel: create(:channel_widget, account: account))
      other_conversation = create(:conversation, account: account, inbox: other_inbox, contact: contact, assignee: agent)

      expect { described_class.new(conversation: other_conversation).enroll! }.not_to change(CadenceEnrollment, :count)
    end
  end
end
