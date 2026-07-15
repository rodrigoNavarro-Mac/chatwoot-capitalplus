require 'rails_helper'

describe Cadences::Analytics::SummaryBuilder do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:cadence_definition) { create_cadence_definition!(whatsapp_inbox) }

  def build_enrollment(status:, current_step: 1)
    contact = create(:contact, account: account, phone_number: format('+1555000%04d', rand(9999)))
    conversation = create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, assignee: agent, status: 'open')
    CadenceEnrollment.create!(
      account: account, conversation: conversation, contact: contact, inbox: whatsapp_inbox,
      cadence_definition: cadence_definition, assignee_id: agent.id,
      status: status, current_step: current_step, last_template_sent_at: 2.hours.ago,
      last_lead_response_at: %w[paused_by_response recovered].include?(status) ? 1.hour.ago : nil
    )
  end

  describe '#build' do
    it 'returns zeroed metrics when there is no data' do
      result = described_class.new(account: account).build

      expect(result[:leads_in_cadence]).to eq(0)
      expect(result[:response_rate]).to eq(0.0)
      expect(result[:call_compliance_rate]).to eq(0.0)
    end

    it 'computes rates without double counting across enrollments' do
      build_enrollment(status: :paused_by_response)
      build_enrollment(status: :waiting_response)
      build_enrollment(status: :cold)

      result = described_class.new(account: account).build

      expect(result[:leads_in_cadence]).to eq(3)
      expect(result[:responded_count]).to eq(1)
      expect(result[:response_rate]).to eq(33.33)
      expect(result[:cold_count]).to eq(1)
    end
  end
end
