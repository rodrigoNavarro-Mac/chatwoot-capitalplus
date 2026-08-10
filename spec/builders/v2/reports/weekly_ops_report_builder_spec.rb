require 'rails_helper'

describe V2::Reports::WeeklyOpsReportBuilder do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp_channel.inbox }
  # `until` un minuto en el futuro (no "ahora mismo") para que los fixtures creados durante el
  # propio test, con timestamp real de la base de datos, no queden justo fuera del rango por el
  # truncamiento a segundos enteros de since/until (ver DateRangeHelper).
  let(:params) { { since: 7.days.ago.to_i.to_s, until: 1.minute.from_now.to_i.to_s } }

  describe '#build' do
    it 'counts new conversations created within the range for this inbox' do
      create(:conversation, account: account, inbox: inbox).update_column(:created_at, 3.days.ago)
      create(:conversation, account: account, inbox: inbox).update_column(:created_at, 20.days.ago)

      result = described_class.new(account: account, inbox: inbox, params: params).build

      expect(result[:volume][:new_conversations]).to eq(1)
    end

    it 'averages first_response/reply_time (in minutes, using business hours) from reporting events within range' do
      create(:reporting_event, account: account, inbox: inbox, name: 'first_response',
                               value: 1200.0, value_in_business_hours: 600.0, created_at: 2.days.ago)
      create(:reporting_event, account: account, inbox: inbox, name: 'first_response',
                               value: 1200.0, value_in_business_hours: 6000.0, created_at: 20.days.ago)

      result = described_class.new(account: account, inbox: inbox, params: params).build

      expect(result[:contact_time][:first_response]).to eq(10.0)
    end

    it 'falls back to the raw value when value_in_business_hours is nil' do
      create(:reporting_event, account: account, inbox: inbox, name: 'reply_time',
                               value: 300.0, value_in_business_hours: nil, created_at: 1.day.ago)

      result = described_class.new(account: account, inbox: inbox, params: params).build

      expect(result[:contact_time][:reply_time]).to eq(5.0)
    end

    it 'returns nil contact time metrics when there are no reporting events in range' do
      result = described_class.new(account: account, inbox: inbox, params: params).build

      expect(result[:contact_time][:first_response]).to be_nil
      expect(result[:contact_time][:reply_time]).to be_nil
    end

    describe 'by_advisor' do
      it 'includes advisors with conversations and/or contact-time events, sorted by conversations_count desc' do
        agent_a = create(:user, account: account, name: 'Agent A')
        agent_b = create(:user, account: account, name: 'Agent B')

        create(:conversation, account: account, inbox: inbox, assignee: agent_a).update_column(:created_at, 2.days.ago)
        create(:conversation, account: account, inbox: inbox, assignee: agent_a).update_column(:created_at, 3.days.ago)
        create(:conversation, account: account, inbox: inbox, assignee: agent_b).update_column(:created_at, 2.days.ago)

        create(:reporting_event, account: account, inbox: inbox, user: agent_a, name: 'first_response',
                                 value_in_business_hours: 600.0, created_at: 2.days.ago)
        create(:reporting_event, account: account, inbox: inbox, user: agent_b, name: 'first_response',
                                 value_in_business_hours: 1200.0, created_at: 2.days.ago)

        result = described_class.new(account: account, inbox: inbox, params: params).build

        expect(result[:by_advisor].map { |advisor| advisor[:name] }).to eq(['Agent A', 'Agent B'])
        expect(result[:by_advisor][0][:conversations_count]).to eq(2)
        expect(result[:by_advisor][0][:contact_time][:first_response]).to eq(10.0)
        expect(result[:by_advisor][1][:conversations_count]).to eq(1)
        expect(result[:by_advisor][1][:contact_time][:first_response]).to eq(20.0)
      end

      it 'returns an empty array when the inbox has no advisor activity in range' do
        result = described_class.new(account: account, inbox: inbox, params: params).build

        expect(result[:by_advisor]).to eq([])
      end
    end

    it 'summarizes cadence enrollments and call tasks for the inbox' do
      cadence_definition = create_cadence_definition!(inbox)
      contact = create(:contact, account: account)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      enrollment = CadenceEnrollment.create!(
        account: account, conversation: conversation, contact: contact, inbox: inbox,
        cadence_definition: cadence_definition, status: 'waiting_response', last_lead_response_at: Time.current
      )
      enrollment.update_column(:created_at, 2.days.ago)
      CadenceCallTask.create!(account: account, cadence_enrollment: enrollment, conversation: conversation, step: 1, status: 'completed')

      result = described_class.new(account: account, inbox: inbox, params: params).build

      expect(result[:cadences][:total_enrollments]).to eq(1)
      expect(result[:cadences][:responded]).to eq(1)
      expect(result[:cadences][:response_rate]).to eq(100.0)
      expect(result[:cadences][:calls_completed]).to eq(1)
      expect(result[:cadences][:calls_pending]).to eq(0)
    end

    it 'summarizes campaign message deliveries for the inbox' do
      campaign = create(:campaign, account: account, inbox: inbox)
      CampaignMessageDelivery.create!(
        account: account, campaign: campaign, phone_number: '+15551234567', audience_type: 'labels',
        sent_at: Time.current, delivered_at: Time.current
      )
      CampaignMessageDelivery.create!(
        account: account, campaign: campaign, phone_number: '+15557654321', audience_type: 'labels'
      )

      result = described_class.new(account: account, inbox: inbox, params: params).build

      expect(result[:campaigns][:campaigns_count]).to eq(1)
      expect(result[:campaigns][:messages_sent]).to eq(1)
      expect(result[:campaigns][:messages_delivered]).to eq(1)
    end

    it 'builds a comparison against the immediately preceding period without recursing further' do
      result = described_class.new(account: account, inbox: inbox, params: params).build

      expect(result[:comparison]).to be_present
      expect(result[:comparison][:comparison]).to be_nil
    end

    it 'omits the comparison when include_comparison is false' do
      result = described_class.new(account: account, inbox: inbox, params: params, include_comparison: false).build

      expect(result[:comparison]).to be_nil
    end
  end
end
