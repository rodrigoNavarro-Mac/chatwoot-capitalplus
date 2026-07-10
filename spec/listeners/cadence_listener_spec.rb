require 'rails_helper'

describe CadenceListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, status: 'open')
  end

  before { account.enable_features!(:whatsapp_cadences) }

  describe '#assignee_changed' do
    let(:event) { Events::Base.new('assignee.changed', Time.zone.now, conversation: conversation) }

    it 'enrolls the conversation when it gains an assignee' do
      conversation.update!(assignee: agent)

      expect { listener.assignee_changed(event) }.to change(CadenceEnrollment, :count).by(1)
    end

    it 'does not enroll when the conversation has no assignee' do
      expect { listener.assignee_changed(event) }.not_to change(CadenceEnrollment, :count)
    end
  end

  describe '#message_created' do
    let!(:enrollment) do
      CadenceEnrollment.create!(
        account: account, conversation: conversation, contact: contact, inbox: whatsapp_inbox, assignee_id: agent.id,
        status: :waiting_response, current_step: 1, last_template_sent_at: 1.hour.ago
      )
    end
    let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }
    let(:event) { Events::Base.new('message.created', Time.zone.now, message: message) }

    it 'pauses the active cadence when the contact replies' do
      listener.message_created(event)

      expect(enrollment.reload.status).to eq('paused_by_response')
    end

    it 'ignores outgoing messages' do
      outgoing_message = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: agent)
      outgoing_event = Events::Base.new('message.created', Time.zone.now, message: outgoing_message)

      listener.message_created(outgoing_event)

      expect(enrollment.reload.status).to eq('waiting_response')
    end
  end
end
