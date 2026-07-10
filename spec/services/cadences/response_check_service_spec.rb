require 'rails_helper'

describe Cadences::ResponseCheckService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, assignee: agent, status: 'open')
  end
  let(:enrollment) do
    CadenceEnrollment.create!(
      account: account, conversation: conversation, contact: contact, inbox: whatsapp_inbox, assignee_id: agent.id,
      status: :waiting_response, current_step: 1, last_template_sent_at: 20.minutes.ago
    )
  end

  before do
    account.enable_features!(:whatsapp_cadences)
    create(:inbox_member, user: agent, inbox: whatsapp_inbox)
  end

  describe '#perform' do
    it 'creates a call task, notifies the agent and schedules the next step' do
      expect { described_class.new(enrollment: enrollment, step: 1).perform }
        .to change(CadenceCallTask, :count).by(1)
        .and change(Notification, :count).by(1)
        .and have_enqueued_job(Cadences::AdvanceJob)

      task = CadenceCallTask.last
      expect(task.step).to eq(1)
      expect(task.user_id).to eq(agent.id)
      expect(task.status).to eq('pending')
      expect(enrollment.reload.status).to eq('pending_agent_call')
    end

    it 'does not create a duplicate call task for the same step' do
      described_class.new(enrollment: enrollment, step: 1).perform

      expect { described_class.new(enrollment: enrollment, step: 1).perform }.not_to change(CadenceCallTask, :count)
    end

    it 'does nothing when the lead already responded' do
      enrollment.update!(last_lead_response_at: Time.current)

      expect { described_class.new(enrollment: enrollment, step: 1).perform }.not_to change(CadenceCallTask, :count)
    end

    it 'marks the cadence cold when the final step gets no response' do
      enrollment.update!(current_step: 6, last_template_sent_at: 1.day.ago)

      described_class.new(enrollment: enrollment, step: 6).perform

      expect(enrollment.reload.status).to eq('cold')
      expect(enrollment.stopped_reason).to eq('no_response_after_cadence')
    end
  end
end
