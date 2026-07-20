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

  let!(:cadence_definition) { create_cadence_definition!(whatsapp_inbox) }

  before { account.enable_features!(:whatsapp_cadences) }

  describe '#assignee_changed' do
    let(:event) { Events::Base.new('assignee.changed', Time.zone.now, conversation: conversation) }

    it 'enrolls the conversation at step 0 when it gains an assignee with no prior template' do
      conversation.update!(assignee: agent)

      expect { listener.assignee_changed(event) }.to change(CadenceEnrollment, :count).by(1)
      expect(CadenceEnrollment.find_by(conversation_id: conversation.id).current_step).to eq(0)
    end

    it 'does not enroll when the conversation has no assignee' do
      expect { listener.assignee_changed(event) }.not_to change(CadenceEnrollment, :count)
    end

    context 'when a template was already sent outside the cadence (e.g. Crm::Zoho::SendInitialTemplateService)' do
      before do
        create(:message, conversation: conversation, account: account, inbox: whatsapp_inbox,
                         message_type: :outgoing, created_at: 2.days.ago,
                         additional_attributes: { template_params: { 'name' => 'cadencia_paso_2', 'language' => 'es_MX' } })
        conversation.update!(assignee: agent)
      end

      it 'enrolls at the step matching the already-sent template instead of repeating step 1' do
        expect { listener.assignee_changed(event) }.to change(CadenceEnrollment, :count).by(1)
        expect(CadenceEnrollment.find_by(conversation_id: conversation.id).current_step).to eq(2)
      end
    end
  end

  describe '#message_created' do
    let!(:enrollment) do
      CadenceEnrollment.create!(
        account: account, conversation: conversation, contact: contact, inbox: whatsapp_inbox,
        cadence_definition: cadence_definition, assignee_id: agent.id,
        status: :waiting_response, current_step: 1, last_template_sent_at: 1.hour.ago,
        steps_snapshot: cadence_steps_snapshot(count: 6)
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
