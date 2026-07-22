require 'rails_helper'

describe Cadences::EnrollConversationService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, status: 'open')
  end

  before do
    account.enable_features!(:whatsapp_cadences)
    create_cadence_steps!(whatsapp_inbox)
  end

  describe '#call' do
    it 'enrolls at step 0 when there is no prior template message' do
      expect { described_class.new(conversation: conversation).call }.to change(CadenceEnrollment, :count).by(1)
      expect(CadenceEnrollment.find_by(conversation_id: conversation.id).current_step).to eq(0)
    end

    it 'resumes at the step matching a template already sent outside the cadence' do
      create(:message, conversation: conversation, account: account, inbox: whatsapp_inbox,
                       message_type: :outgoing, created_at: 2.days.ago,
                       additional_attributes: { template_params: { 'name' => 'cadencia_paso_2', 'language' => 'es_MX' } })

      expect { described_class.new(conversation: conversation).call }.to change(CadenceEnrollment, :count).by(1)
      expect(CadenceEnrollment.find_by(conversation_id: conversation.id).current_step).to eq(2)
    end

    it 'does nothing when the conversation is already enrolled' do
      Cadences::EnrollmentService.new(conversation: conversation).enroll!

      expect { described_class.new(conversation: conversation).call }.not_to change(CadenceEnrollment, :count)
    end

    it 'does nothing when the conversation is not eligible' do
      account.disable_features!(:whatsapp_cadences)

      expect { described_class.new(conversation: conversation).call }.not_to change(CadenceEnrollment, :count)
    end

    it 'does not raise when the underlying enrollment services error out' do
      allow(Cadences::PastLeadEnrollmentService).to receive(:new).and_raise(StandardError, 'boom')

      expect { described_class.new(conversation: conversation).call }.not_to raise_error
    end
  end
end
