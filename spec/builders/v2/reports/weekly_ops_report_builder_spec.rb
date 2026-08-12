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
      it 'includes advisors with assigned conversations, sorted by conversations_count desc' do
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

      it 'excludes agents with contact-time events but no assigned conversations in range' do
        agent = create(:user, account: account, name: 'Agent Without Assignments')
        create(:reporting_event, account: account, inbox: inbox, user: agent, name: 'first_response',
                                 value_in_business_hours: 600.0, created_at: 2.days.ago)

        result = described_class.new(account: account, inbox: inbox, params: params).build

        expect(result[:by_advisor]).to eq([])
      end
    end

    describe 'zoho_leads' do
      it 'is nil when the inbox has no desarrollo configured' do
        result = described_class.new(account: account, inbox: inbox, params: params).build

        expect(result[:zoho_leads]).to be_nil
      end

      it 'summarizes status, source and discard reason distribution from Zoho leads for this desarrollo/period' do
        agent_bot = create(:agent_bot, account: account, bot_config: { 'variables' => { 'desarrollo' => 'Fuego' } })
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        leads = [
          { 'Lead_Status' => 'Contacted', 'Lead_Source' => 'Facebook Ads' },
          { 'Lead_Status' => 'Contacted', 'Lead_Source' => 'Facebook Ads' },
          { 'Lead_Status' => 'Attempted to Contact', 'Lead_Source' => 'Google Ads' },
          { 'Lead_Status' => 'Lost Lead', 'Lead_Source' => 'Facebook Ads', 'Raz_n_de_descarte' => 'NO TUVO PRESUPUESTO' }
        ]
        fake_service = instance_double(Crm::Zoho::LeadsForPeriodService, fetch: leads)
        allow(Crm::Zoho::LeadsForPeriodService).to receive(:new)
          .with(account: account, development_key: 'Fuego', range: anything)
          .and_return(fake_service)

        result = described_class.new(account: account, inbox: inbox, params: params).build

        expect(result[:zoho_leads][:total]).to eq(4)
        expect(result[:zoho_leads][:by_status]).to eq('Contactado' => 2, 'Intento de contacto' => 1, 'Cliente perdido/Descartado' => 1)
        expect(result[:zoho_leads][:by_source]).to eq('Facebook Ads' => 3, 'Google Ads' => 1)
        expect(result[:zoho_leads][:discard_reasons]).to eq('NO TUVO PRESUPUESTO' => 1)
        expect(result[:zoho_leads][:quality_leads_count]).to eq(2)
        expect(result[:zoho_leads][:quality_leads_percent]).to eq(50.0)
      end
    end

    describe 'zoho_leads_timeline' do
      it 'is nil when the inbox has no desarrollo configured' do
        result = described_class.new(account: account, inbox: inbox, params: params).build

        expect(result[:zoho_leads_timeline]).to be_nil
      end

      it 'buckets leads by day for a week-type report, and reuses the same Zoho fetch as zoho_leads_metrics' do
        agent_bot = create(:agent_bot, account: account, bot_config: { 'variables' => { 'desarrollo' => 'Fuego' } })
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        leads = [
          { 'Created_Time' => 2.days.ago.iso8601, 'Lead_Status' => 'Contacted' },
          { 'Created_Time' => 2.days.ago.iso8601, 'Lead_Status' => 'Contacted' },
          { 'Created_Time' => 1.day.ago.iso8601, 'Lead_Status' => 'Contacted' }
        ]
        fake_service = instance_double(Crm::Zoho::LeadsForPeriodService, fetch: leads)
        allow(Crm::Zoho::LeadsForPeriodService).to receive(:new).and_return(fake_service)

        result = described_class.new(account: account, inbox: inbox, params: params.merge(period_type: 'week'), include_comparison: false).build

        expect(result[:zoho_leads_timeline][:granularity]).to eq('day')
        expect(result[:zoho_leads_timeline][:counts].sum).to eq(3)
        # zoho_leads_metrics y zoho_leads_timeline comparten la misma llamada memoizada a Zoho.
        expect(fake_service).to have_received(:fetch).once
      end

      it 'still returns a full zero-filled timeline when there are no leads in range' do
        agent_bot = create(:agent_bot, account: account, bot_config: { 'variables' => { 'desarrollo' => 'Fuego' } })
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        fake_service = instance_double(Crm::Zoho::LeadsForPeriodService, fetch: [])
        allow(Crm::Zoho::LeadsForPeriodService).to receive(:new).and_return(fake_service)

        result = described_class.new(account: account, inbox: inbox, params: params).build

        expect(result[:zoho_leads_timeline][:counts]).to all(eq(0))
        expect(result[:zoho_leads_timeline][:labels]).not_to be_empty
      end

      it 'uses week granularity for a month-type report, and month granularity for a quarter-type report' do
        agent_bot = create(:agent_bot, account: account, bot_config: { 'variables' => { 'desarrollo' => 'Fuego' } })
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        fake_service = instance_double(Crm::Zoho::LeadsForPeriodService, fetch: [])
        allow(Crm::Zoho::LeadsForPeriodService).to receive(:new).and_return(fake_service)

        month_result = described_class.new(account: account, inbox: inbox, params: params.merge(period_type: 'month')).build
        quarter_result = described_class.new(account: account, inbox: inbox, params: params.merge(period_type: 'quarter')).build

        expect(month_result[:zoho_leads_timeline][:granularity]).to eq('week')
        expect(quarter_result[:zoho_leads_timeline][:granularity]).to eq('month')
      end
    end

    describe 'aircall_calls' do
      it 'is nil when the inbox has no Aircall calls in range' do
        result = described_class.new(account: account, inbox: inbox, params: params).build

        expect(result[:aircall_calls]).to be_nil
      end

      it 'summarizes total, answered rate, average duration and direction for Aircall calls in range' do
        conversation = create(:conversation, account: account, inbox: inbox)
        create(:call, conversation: conversation, provider: :aircall, direction: :incoming,
                      status: 'completed', duration_seconds: 120, started_at: 2.days.ago)
        create(:call, conversation: conversation, provider: :aircall, direction: :incoming,
                      status: 'completed', duration_seconds: 60, started_at: 2.days.ago)
        create(:call, conversation: conversation, provider: :aircall, direction: :outgoing,
                      status: 'no_answer', started_at: 2.days.ago)
        create(:call, conversation: conversation, provider: :twilio, status: 'completed', started_at: 2.days.ago)

        result = described_class.new(account: account, inbox: inbox, params: params).build

        expect(result[:aircall_calls][:total]).to eq(3)
        expect(result[:aircall_calls][:answered]).to eq(2)
        expect(result[:aircall_calls][:answered_percent]).to eq(66.67)
        expect(result[:aircall_calls][:avg_duration_seconds]).to eq(90)
        expect(result[:aircall_calls][:incoming]).to eq(2)
        expect(result[:aircall_calls][:outgoing]).to eq(1)
      end

      it 'breaks down calls by the agent who accepted/made them, sorted by total desc' do
        agent_a = create(:user, account: account, name: 'Agent A')
        agent_b = create(:user, account: account, name: 'Agent B')
        conversation = create(:conversation, account: account, inbox: inbox)
        create(:call, conversation: conversation, provider: :aircall, status: 'completed',
                      duration_seconds: 100, accepted_by_agent: agent_a, started_at: 2.days.ago)
        create(:call, conversation: conversation, provider: :aircall, status: 'no_answer',
                      accepted_by_agent: agent_a, started_at: 2.days.ago)
        create(:call, conversation: conversation, provider: :aircall, status: 'completed',
                      duration_seconds: 200, accepted_by_agent: agent_b, started_at: 2.days.ago)

        result = described_class.new(account: account, inbox: inbox, params: params).build
        by_advisor = result[:aircall_calls][:by_advisor]

        expect(by_advisor.map { |a| a[:name] }).to eq(['Agent A', 'Agent B'])
        expect(by_advisor[0][:total]).to eq(2)
        expect(by_advisor[0][:answered]).to eq(1)
        expect(by_advisor[0][:avg_duration_seconds]).to eq(100)
        expect(by_advisor[1][:total]).to eq(1)
        expect(by_advisor[1][:avg_duration_seconds]).to eq(200)
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
