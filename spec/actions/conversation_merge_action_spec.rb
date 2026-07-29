require 'rails_helper'

describe ConversationMergeAction do
  subject(:conversation_merge) do
    described_class.new(account: account, base_conversation: base_conversation, mergee_conversation: mergee_conversation).perform
  end

  let!(:account) { create(:account) }
  let!(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:base_conversation) { create(:conversation, account: account, contact: contact, inbox: inbox) }
  let!(:mergee_conversation) { create(:conversation, account: account, contact: contact, inbox: inbox) }

  let!(:mergee_messages) { create_list(:message, 2, conversation: mergee_conversation, account: account, inbox: inbox) }

  describe '#perform' do
    it 'deletes the mergee conversation' do
      conversation_merge
      expect { mergee_conversation.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'moves the messages to the base conversation' do
      conversation_merge
      expect(base_conversation.reload.messages.pluck(:id)).to include(*mergee_messages.map(&:id))
    end

    it 'returns the base conversation' do
      expect(conversation_merge).to eq(base_conversation)
    end

    context 'when base and mergee conversation are the same' do
      it 'does not delete the conversation' do
        described_class.new(account: account, base_conversation: base_conversation, mergee_conversation: base_conversation).perform
        expect(base_conversation.reload).to be_present
      end
    end

    context 'when conversations belong to a different account' do
      it 'raises an error' do
        other_account_conversation = create(:conversation)
        expect do
          described_class.new(account: account, base_conversation: base_conversation, mergee_conversation: other_account_conversation).perform
        end.to raise_error('conversation does not belong to the account')
      end
    end

    context 'when conversations belong to different contacts' do
      it 'raises an error' do
        other_contact_conversation = create(:conversation, account: account, inbox: inbox)
        expect do
          described_class.new(account: account, base_conversation: base_conversation, mergee_conversation: other_contact_conversation).perform
        end.to raise_error('conversations must belong to the same contact')
      end
    end

    context 'when only the mergee conversation has a cadence enrollment' do
      before { account.enable_features!(:whatsapp_cadences) }

      let!(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
      let!(:whatsapp_inbox) { whatsapp_channel.inbox }
      let!(:cadence_definition) { create_cadence_definition!(whatsapp_inbox) } # rubocop:disable RSpec/LetSetup
      let!(:base_conversation) { create(:conversation, account: account, contact: contact, inbox: whatsapp_inbox, assignee: nil) }
      let!(:mergee_conversation) { create(:conversation, account: account, contact: contact, inbox: whatsapp_inbox, assignee: nil) }
      let!(:enrollment) { Cadences::EnrollmentService.new(conversation: mergee_conversation).enroll! }

      it 'transfers the enrollment to the base conversation' do
        conversation_merge
        expect(enrollment.reload.conversation_id).to eq(base_conversation.id)
      end
    end

    context 'when both conversations already have a cadence enrollment' do
      before { account.enable_features!(:whatsapp_cadences) }

      let!(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
      let!(:whatsapp_inbox) { whatsapp_channel.inbox }
      let!(:cadence_definition) { create_cadence_definition!(whatsapp_inbox) } # rubocop:disable RSpec/LetSetup
      let!(:base_conversation) { create(:conversation, account: account, contact: contact, inbox: whatsapp_inbox, assignee: nil) }
      let!(:mergee_conversation) { create(:conversation, account: account, contact: contact, inbox: whatsapp_inbox, assignee: nil) }
      let!(:base_enrollment) { Cadences::EnrollmentService.new(conversation: base_conversation).enroll! }
      let!(:mergee_enrollment) { Cadences::EnrollmentService.new(conversation: mergee_conversation).enroll! }

      it "keeps the base conversation's enrollment and lets the mergee's be destroyed with its conversation" do
        conversation_merge
        expect { mergee_enrollment.reload }.to raise_error(ActiveRecord::RecordNotFound)
        expect(base_enrollment.reload.status).not_to eq('failed')
        expect(base_enrollment.conversation_id).to eq(base_conversation.id)
      end
    end
  end
end
