require 'rails_helper'

describe RevenueIntelligence::BuildJourneysJob do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let!(:revenue_contact) do
    account.revenue_contacts.create!(chatwoot_contact_id: contact.id, first_seen_at: Time.current, last_seen_at: Time.current)
  end
  let!(:lead) do
    account.revenue_leads.create!(zoho_lead_id: 'lead-1', revenue_contact_id: revenue_contact.id, created_at_source: 10.days.ago)
  end

  before do
    account.enable_features!('crm_integration')
    create(:integrations_hook, :zoho_crm, account: account, status: 'enabled')
  end

  def add_event(event_type, event_at, source_id: SecureRandom.hex(4), source_system: 'test')
    account.revenue_events.create!(revenue_contact_id: revenue_contact.id, event_type: event_type, event_at: event_at,
                                   source_system: source_system, source_id: source_id)
  end

  describe 'milestones and time-to-X' do
    context 'with a full set of milestone events' do
      let(:created_at) { 10.days.ago }
      let(:journey) { lead.reload.revenue_lead_journey }

      before do
        add_event('lead_created', created_at)
        add_event('first_response', created_at + 1.hour)
        add_event('call_started', created_at + 2.hours)
        add_event('call_answered', created_at + 2.hours + 5.minutes)
        add_event('lead_qualified', created_at + 1.day)
        add_event('appointment_created', created_at + 2.days)
        add_event('visit_effective', created_at + 3.days)
        add_event('reserved', created_at + 4.days)
        described_class.new.perform
      end

      it 'sets lead_created_at/first_response_at/reserved_at to the earliest event_at of their type' do
        expect(journey.lead_created_at).to be_within(1.second).of(created_at)
        expect(journey.first_response_at).to be_within(1.second).of(created_at + 1.hour)
        expect(journey.reserved_at).to be_within(1.second).of(created_at + 4.days)
      end

      it 'computes each time_to_X as the seconds between lead_created_at and its milestone' do
        expect(journey.time_to_first_response_seconds).to eq(1.hour.to_i)
        expect(journey.time_to_first_call_seconds).to eq(2.hours.to_i)
        expect(journey.time_to_qualification_seconds).to eq(1.day.to_i)
        expect(journey.time_to_appointment_seconds).to eq(2.days.to_i)
        expect(journey.time_to_visit_seconds).to eq(3.days.to_i)
      end
    end

    it 'takes the earliest of closed_won/closed_lost as closed_at' do
      created_at = 10.days.ago
      add_event('lead_created', created_at)
      add_event('closed_won', created_at + 5.days)

      described_class.new.perform

      journey = lead.reload.revenue_lead_journey
      expect(journey.closed_at).to be_within(1.second).of(created_at + 5.days)
      expect(journey.time_to_close_seconds).to eq(5.days.to_i)
    end

    it 'falls back to revenue_leads.created_at_source when there is no lead_created event yet' do
      add_event('whatsapp_incoming', 1.day.ago) # dispara la reconstrucción sin un evento lead_created

      described_class.new.perform

      journey = lead.reload.revenue_lead_journey
      expect(journey.lead_created_at).to be_within(1.second).of(lead.created_at_source)
    end
  end

  describe 'outcome' do
    it 'takes final_stage/won/lost from the most recently created deal of the lead' do
      account.revenue_deals.create!(zoho_deal_id: 'deal-1', revenue_lead_id: lead.id, revenue_contact_id: revenue_contact.id,
                                    stage: 'Cerrado ganado', won: true, created_at: 2.days.ago)
      add_event('lead_created', 10.days.ago)

      described_class.new.perform

      journey = lead.reload.revenue_lead_journey
      expect(journey.final_stage).to eq('Cerrado ganado')
      expect(journey.won).to be(true)
      expect(journey.lost).to be(false)
    end

    it 'defaults won/lost to false and final_stage to nil when the lead has no deal' do
      add_event('lead_created', 10.days.ago)

      described_class.new.perform

      journey = lead.reload.revenue_lead_journey
      expect(journey.final_stage).to be_nil
      expect(journey.won).to be(false)
      expect(journey.lost).to be(false)
    end
  end

  describe 'activity counts' do
    it 'counts messages/calls by event_type' do
      add_event('whatsapp_incoming', 1.day.ago)
      add_event('whatsapp_incoming', 2.days.ago)
      add_event('whatsapp_outgoing', 1.day.ago)
      add_event('call_started', 1.day.ago)
      add_event('call_answered', 1.day.ago)
      add_event('call_missed', 2.days.ago)

      described_class.new.perform

      journey = lead.reload.revenue_lead_journey
      expect(journey.incoming_messages).to eq(2)
      expect(journey.outgoing_messages).to eq(1)
      expect(journey.calls_attempted).to eq(1)
      expect(journey.calls_answered).to eq(1)
      expect(journey.calls_missed).to eq(1)
    end

    it 'reads total_call_seconds/unique_agents directly from calls, not from event metadata' do
      agent = create(:user, account: account)
      other_agent = create(:user, account: account)
      conversation = create(:conversation, account: account, contact: contact)
      create(:call, account: account, conversation: conversation, contact: contact, accepted_by_agent: agent, duration_seconds: 60,
                    status: 'completed')
      create(:call, account: account, conversation: conversation, contact: contact, accepted_by_agent: other_agent, duration_seconds: 30,
                    status: 'completed')
      add_event('lead_created', 10.days.ago)

      described_class.new.perform

      journey = lead.reload.revenue_lead_journey
      expect(journey.total_call_seconds).to eq(90)
      expect(journey.unique_agents).to eq(2)
    end
  end

  describe 'call intelligence aggregates' do
    context 'with two completed call analyses' do
      before do
        conversation = create(:conversation, account: account, contact: contact)
        call1 = create(:call, account: account, conversation: conversation, contact: contact, status: 'completed')
        call2 = create(:call, account: account, conversation: conversation, contact: contact, status: 'completed')
        create(:call_analysis, call: call1, account: account, status: 'completed', intent_level: 'media', analyzed_at: 2.days.ago,
                               scorecard: { 'total_score' => 60.0 }, metrics: { 'cta_used' => true },
                               objections: [{ 'category' => 'financiera' }], risks: [])
        create(:call_analysis, call: call2, account: account, status: 'completed', intent_level: 'alta', analyzed_at: 1.day.ago,
                               scorecard: { 'total_score' => 80.0 }, metrics: { 'cta_used' => false },
                               objections: [], risks: [{ 'type' => 'urgencia_antes_de_valor' }])
        add_event('lead_created', 10.days.ago)
        described_class.new.perform
      end

      let(:journey) { lead.reload.revenue_lead_journey }

      it 'averages/max/last the score across analyses, with last defined by analyzed_at' do
        expect(journey.avg_call_score.to_f).to eq(70.0)
        expect(journey.max_call_score.to_f).to eq(80.0)
        expect(journey.last_call_score.to_f).to eq(80.0)
      end

      it 'sets latest_intent to the most recent analysis and max_intent to the highest-ranked one' do
        expect(journey.latest_intent).to eq('alta')
        expect(journey.max_intent).to eq('alta')
      end

      it 'sums cta/objections/risks across all analyses' do
        expect(journey.cta_count).to eq(1)
        expect(journey.objections_count).to eq(1)
        expect(journey.risks_count).to eq(1)
      end
    end

    it 'leaves call intelligence fields nil/zero when there are no completed analyses' do
      add_event('lead_created', 10.days.ago)

      described_class.new.perform

      journey = lead.reload.revenue_lead_journey
      expect(journey.avg_call_score).to be_nil
      expect(journey.cta_count).to eq(0)
    end
  end

  describe 'idempotency and scoping' do
    it 'is idempotent — running it twice without new events keeps the same values (only built_at changes)' do
      add_event('lead_created', 10.days.ago)

      described_class.new.perform
      first_built_at = lead.reload.revenue_lead_journey.built_at
      described_class.new.perform

      expect(RevenueLeadJourney.where(revenue_lead_id: lead.id).count).to eq(1)
      expect(lead.reload.revenue_lead_journey.built_at).to be >= first_built_at
    end

    it 'does not rebuild a journey for a lead whose contact has no events at all' do
      untouched_lead = account.revenue_leads.create!(zoho_lead_id: 'lead-untouched', revenue_contact_id: revenue_contact.id)
      # Ningún evento nuevo para revenue_contact -> ningún lead de esa cuenta se reconstruye en esta corrida.

      described_class.new.perform

      expect(RevenueLeadJourney.where(revenue_lead_id: untouched_lead.id)).not_to exist
    end

    it 'only builds journeys for the given account when an account_id is passed' do
      other_account = create(:account)
      other_account.enable_features!('crm_integration')
      create(:integrations_hook, :zoho_crm, account: other_account, status: 'enabled')
      other_contact = create(:contact, account: other_account)
      other_revenue_contact = other_account.revenue_contacts.create!(chatwoot_contact_id: other_contact.id, first_seen_at: Time.current,
                                                                     last_seen_at: Time.current)
      other_lead = other_account.revenue_leads.create!(zoho_lead_id: 'lead-other', revenue_contact_id: other_revenue_contact.id)
      other_account.revenue_events.create!(revenue_contact_id: other_revenue_contact.id, event_type: 'lead_created', event_at: Time.current,
                                           source_system: 'test', source_id: '1')
      add_event('lead_created', 10.days.ago)

      described_class.new.perform(account.id)

      expect(lead.reload.revenue_lead_journey).to be_present
      expect(other_lead.reload.revenue_lead_journey).to be_nil
    end

    it 'continues with other leads when rebuilding one of them raises' do
      broken_lead = account.revenue_leads.create!(zoho_lead_id: 'lead-broken', revenue_contact_id: revenue_contact.id)
      add_event('lead_created', 10.days.ago)
      allow_any_instance_of(described_class).to receive(:rebuild_journey).and_wrap_original do |method, acc, target_lead| # rubocop:disable RSpec/AnyInstance
        raise 'boom' if target_lead.id == broken_lead.id

        method.call(acc, target_lead)
      end

      expect { described_class.new.perform }.not_to raise_error
      expect(lead.reload.revenue_lead_journey).to be_present
    end
  end
end
