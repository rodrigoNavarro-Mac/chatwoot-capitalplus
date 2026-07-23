require 'rails_helper'

describe Cadences::Analytics::StepsBuilder do
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
      status: :waiting_response, current_step: 1, last_template_sent_at: 2.hours.ago
    )
  end

  describe '#build' do
    it 'returns no rows when nothing was ever sent' do
      expect(described_class.new(account: account).build).to eq([])
    end

    it 'derives steps from observed CadenceEvent rows, not a fixed list' do
      CadenceEvent.create!(
        account: account, cadence_enrollment: enrollment, conversation: conversation, contact: contact,
        event_type: 'template_sent', step: 1, template_key: 'wa_paso_1', occurred_at: Time.current
      )
      CadenceEvent.create!(
        account: account, cadence_enrollment: enrollment, conversation: conversation, contact: contact,
        event_type: 'template_sent', step: 9, template_key: 'wa_paso_9', occurred_at: Time.current
      )

      result = described_class.new(account: account).build

      expect(result.map { |row| row[:step] }).to eq([1, 9])
      expect(result.find { |row| row[:step] == 9 }[:template_key]).to eq('wa_paso_9')
    end

    it 'computes drop_off_rate against the previous step, and 0.0 for the first step' do
      contact_2 = create(:contact, account: account, phone_number: '+15557654321')
      conversation_2 = create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact_2, assignee: agent, status: 'open')
      enrollment_2 = CadenceEnrollment.create!(
        account: account, conversation: conversation_2, contact: contact_2, inbox: whatsapp_inbox,
        cadence_definition: cadence_definition, assignee_id: agent.id,
        status: :waiting_response, current_step: 1, last_template_sent_at: 2.hours.ago
      )

      # Paso 1: enviado a 2 leads. Paso 2: enviado solo a 1 (el otro abandonó tras el paso 1).
      [enrollment, enrollment_2].each do |enr|
        CadenceEvent.create!(
          account: account, cadence_enrollment: enr, conversation: enr.conversation, contact: enr.contact,
          event_type: 'template_sent', step: 1, template_key: 'wa_paso_1', occurred_at: Time.current
        )
      end
      CadenceEvent.create!(
        account: account, cadence_enrollment: enrollment, conversation: conversation, contact: contact,
        event_type: 'template_sent', step: 2, template_key: 'wa_paso_2', occurred_at: Time.current
      )

      result = described_class.new(account: account).build

      step_1 = result.find { |row| row[:step] == 1 }
      step_2 = result.find { |row| row[:step] == 2 }

      expect(step_1[:sent]).to eq(2)
      expect(step_1[:drop_off_rate]).to eq(0.0)
      expect(step_2[:sent]).to eq(1)
      expect(step_2[:drop_off_rate]).to eq(50.0)
    end
  end
end
