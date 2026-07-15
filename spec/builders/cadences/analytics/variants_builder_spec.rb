require 'rails_helper'

describe Cadences::Analytics::VariantsBuilder do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }

  def build_enrollment(cadence_definition, status: :active)
    contact = create(:contact, account: account, phone_number: format('+1555000%04d', rand(9999)))
    conversation = create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, assignee: agent, status: 'open')
    CadenceEnrollment.create!(
      account: account, conversation: conversation, contact: contact, inbox: whatsapp_inbox,
      cadence_definition: cadence_definition, assignee_id: agent.id, status: status,
      last_template_sent_at: 2.hours.ago,
      last_lead_response_at: %w[paused_by_response recovered].include?(status.to_s) ? 1.hour.ago : nil
    )
  end

  describe '#build' do
    it 'returns one row per active cadence definition of the inbox, even with zero leads' do
      CadenceDefinition.create!(account: account, inbox: whatsapp_inbox, name: 'Default', is_default: true)

      result = described_class.new(account: account, filters: { inbox_id: whatsapp_inbox.id }).build

      expect(result.size).to eq(1)
      expect(result.first[:leads_in_cadence]).to eq(0)
      expect(result.first[:response_rate]).to eq(0.0)
    end

    it 'breaks down metrics per variant, so A and B can be compared side by side' do
      variant_a = CadenceDefinition.create!(account: account, inbox: whatsapp_inbox, name: 'A', segment_value: 'Inversión')
      variant_b = CadenceDefinition.create!(account: account, inbox: whatsapp_inbox, name: 'B', segment_value: 'Inversión')

      build_enrollment(variant_a, status: :paused_by_response)
      build_enrollment(variant_a, status: :waiting_response)
      build_enrollment(variant_b, status: :cold)

      result = described_class.new(account: account, filters: { inbox_id: whatsapp_inbox.id }).build

      row_a = result.find { |row| row[:id] == variant_a.id }
      row_b = result.find { |row| row[:id] == variant_b.id }

      expect(row_a[:leads_in_cadence]).to eq(2)
      expect(row_a[:responded_count]).to eq(1)
      expect(row_a[:response_rate]).to eq(50.0)
      expect(row_b[:leads_in_cadence]).to eq(1)
      expect(row_b[:cold_count]).to eq(1)
    end

    it 'ignores inactive cadence definitions' do
      CadenceDefinition.create!(account: account, inbox: whatsapp_inbox, name: 'Archived', active: false)

      result = described_class.new(account: account, filters: { inbox_id: whatsapp_inbox.id }).build

      expect(result).to be_empty
    end

    it 'still shows all variants even when the general cadence_definition_id filter is set to one of them' do
      variant_a = CadenceDefinition.create!(account: account, inbox: whatsapp_inbox, name: 'A', segment_value: 'Inversión')
      variant_b = CadenceDefinition.create!(account: account, inbox: whatsapp_inbox, name: 'B', segment_value: 'Inversión')

      result = described_class.new(
        account: account, filters: { inbox_id: whatsapp_inbox.id, cadence_definition_id: variant_a.id }
      ).build

      expect(result.map { |row| row[:id] }).to contain_exactly(variant_a.id, variant_b.id)
    end
  end
end
