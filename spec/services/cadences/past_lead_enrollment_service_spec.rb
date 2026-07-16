require 'rails_helper'

describe Cadences::PastLeadEnrollmentService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false)
  end
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

  def send_template_message(name:, language: 'es_MX', sent_at: 2.days.ago)
    create(:message, conversation: conversation, account: account, inbox: whatsapp_inbox,
                     message_type: :outgoing, created_at: sent_at,
                     additional_attributes: { template_params: { 'name' => name, 'language' => language } })
  end

  def reply_message(created_at:)
    create(:message, conversation: conversation, account: account, inbox: whatsapp_inbox,
                     message_type: :incoming, created_at: created_at)
  end

  describe '#call' do
    it 'skips a conversation already enrolled in a cadence' do
      Cadences::EnrollmentService.new(conversation: conversation).enroll!

      result = described_class.new(conversation: conversation).call

      expect(result.status).to eq(:skipped)
      expect(result.detail).to eq('already_enrolled')
    end

    it 'skips a conversation that is not eligible (no assignee)' do
      conversation.update!(assignee: nil)
      send_template_message(name: 'cadencia_paso_1')

      result = described_class.new(conversation: conversation).call

      expect(result.status).to eq(:skipped)
      expect(result.detail).to eq('not_eligible')
    end

    it 'skips a conversation with no template sent yet' do
      result = described_class.new(conversation: conversation).call

      expect(result.status).to eq(:skipped)
      expect(result.detail).to eq('no_template_sent')
    end

    it 'skips when the last template sent does not match any configured step' do
      send_template_message(name: 'plantilla_no_configurada')

      result = described_class.new(conversation: conversation).call

      expect(result.status).to eq(:skipped)
      expect(result.detail).to eq('no_matching_step')
    end

    it 'enrolls at the matching step and schedules a response check when the lead has not replied' do
      send_template_message(name: 'cadencia_paso_2', sent_at: 3.days.ago)

      result = described_class.new(conversation: conversation).call
      enrollment = CadenceEnrollment.find_by(conversation_id: conversation.id)

      expect(result.status).to eq(:enrolled)
      expect(enrollment.current_step).to eq(2)
      expect(enrollment.status).to eq('waiting_response')
      expect(enrollment.last_lead_response_at).to be_nil
      expect(enrollment.cadence_events.pluck(:event_type)).to contain_exactly('cadence_started', 'template_sent')
      expect(Cadences::CheckResponseJob).to have_been_enqueued.with(enrollment.id, 2)
    end

    it 'marks the enrollment as paused_by_response when the lead already replied and more steps remain' do
      sent_at = 3.days.ago
      send_template_message(name: 'cadencia_paso_1', sent_at: sent_at)
      reply_message(created_at: sent_at + 1.hour)

      described_class.new(conversation: conversation).call
      enrollment = CadenceEnrollment.find_by(conversation_id: conversation.id)

      expect(enrollment.status).to eq('paused_by_response')
      expect(enrollment.next_action_at).to be_nil
      expect(enrollment.cadence_events.pluck(:event_type)).to contain_exactly('cadence_started', 'template_sent', 'lead_replied', 'cadence_paused')
    end

    it 'marks the enrollment as recovered when the lead already replied to the last configured step' do
      sent_at = 3.days.ago
      send_template_message(name: 'cadencia_paso_3', sent_at: sent_at)
      reply_message(created_at: sent_at + 1.hour)

      described_class.new(conversation: conversation).call
      enrollment = CadenceEnrollment.find_by(conversation_id: conversation.id)

      expect(enrollment.status).to eq('recovered')
      expect(enrollment.cadence_events.pluck(:event_type)).to include('cadence_recovered')
    end

    it 'is idempotent: calling it twice only enrolls once' do
      send_template_message(name: 'cadencia_paso_1')

      described_class.new(conversation: conversation).call
      second_result = described_class.new(conversation: conversation).call

      expect(second_result.status).to eq(:skipped)
      expect(CadenceEnrollment.where(conversation_id: conversation.id).count).to eq(1)
    end
  end
end
