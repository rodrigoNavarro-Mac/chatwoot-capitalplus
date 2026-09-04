require 'rails_helper'

describe RevenueIntelligence::BuildEventsJob do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact) }
  let!(:revenue_contact) do
    account.revenue_contacts.create!(chatwoot_contact_id: contact.id, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  before do
    account.enable_features!('crm_integration')
    create(:integrations_hook, :zoho_crm, account: account, status: 'enabled')
  end

  describe 'message events' do
    it 'creates whatsapp_incoming/whatsapp_outgoing events only for WhatsApp inbox messages of a resolved contact' do
      incoming = create(:message, account: account, conversation: conversation, message_type: 'incoming')
      outgoing = create(:message, account: account, conversation: conversation, message_type: 'outgoing')
      other_inbox_conversation = create(:conversation, account: account) # widget inbox, no WhatsApp
      create(:message, account: account, conversation: other_inbox_conversation, message_type: 'incoming')

      described_class.new.perform

      expect(account.revenue_events.find_by(source_id: incoming.id.to_s, event_type: 'whatsapp_incoming')).to be_present
      expect(account.revenue_events.find_by(source_id: outgoing.id.to_s, event_type: 'whatsapp_outgoing')).to be_present
      expect(account.revenue_events.where(source_system: 'chatwoot_message').count).to eq(2)
    end

    it 'does not create a message event for a contact without a resolved revenue_contact' do
      unresolved_contact = create(:contact, account: account)
      unresolved_conversation = create(:conversation, account: account, inbox: whatsapp_inbox, contact: unresolved_contact)
      create(:message, account: account, conversation: unresolved_conversation, message_type: 'incoming')

      described_class.new.perform

      expect(account.revenue_events.where(source_system: 'chatwoot_message')).to be_empty
    end

    it 'is idempotent — running it twice does not duplicate message events' do
      create(:message, account: account, conversation: conversation, message_type: 'incoming')

      described_class.new.perform
      described_class.new.perform

      expect(account.revenue_events.where(source_system: 'chatwoot_message').count).to eq(1)
    end
  end

  describe 'first_response events' do
    it 'creates a first_response event from conversation.first_reply_created_at' do
      conversation.update!(first_reply_created_at: Time.current)

      described_class.new.perform

      event = account.revenue_events.find_by(source_system: 'conversation', event_type: 'first_response')
      expect(event.revenue_contact_id).to eq(revenue_contact.id)
    end
  end

  describe 'call events' do
    it 'always creates call_started, and adds call_answered when the call completed' do
      call = create(:call, account: account, conversation: conversation, contact: contact, status: 'completed', started_at: Time.current,
                           duration_seconds: 90)

      described_class.new.perform

      expect(account.revenue_events.find_by(source_id: call.id.to_s, event_type: 'call_started')).to be_present
      expect(account.revenue_events.find_by(source_id: call.id.to_s, event_type: 'call_answered')).to be_present
    end

    it 'creates call_missed instead of call_answered for a no_answer call' do
      call = create(:call, account: account, conversation: conversation, contact: contact, status: 'no_answer', started_at: Time.current)

      described_class.new.perform

      expect(account.revenue_events.find_by(source_id: call.id.to_s, event_type: 'call_missed')).to be_present
      expect(account.revenue_events.find_by(source_id: call.id.to_s, event_type: 'call_answered')).to be_nil
    end

    it 'does not create a resolution event for a call still ringing' do
      call = create(:call, account: account, conversation: conversation, contact: contact, status: 'ringing', started_at: Time.current)

      described_class.new.perform

      expect(account.revenue_events.find_by(source_id: call.id.to_s, event_type: 'call_started')).to be_present
      expect(account.revenue_events.where(source_id: call.id.to_s, event_type: %w[call_answered call_missed])).to be_empty
    end
  end

  describe 'call_analyzed events' do
    it 'creates a call_analyzed event with score/intent/confidence in metadata' do
      call = create(:call, account: account, conversation: conversation, contact: contact, status: 'completed', started_at: Time.current)
      analysis = create(:call_analysis, call: call, account: account, status: 'completed', intent_level: 'alta', confidence: 'high',
                                        scorecard: { 'total_score' => 82.5 })

      described_class.new.perform

      event = account.revenue_events.find_by(source_system: 'call_analysis', source_id: analysis.id.to_s)
      expect(event.metadata).to eq('score' => 82.5, 'intent_level' => 'alta', 'confidence' => 'high')
    end
  end

  describe 'lead milestone events' do
    it 'creates lead_created, lead_contacted and lead_qualified as distinct events for the same lead' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', revenue_contact_id: revenue_contact.id, created_at_source: 3.days.ago,
                                           first_contact_at: 2.days.ago, qualified_at: 1.day.ago)

      described_class.new.perform

      types = account.revenue_events.where(source_system: 'revenue_lead', source_id: lead.id.to_s).pluck(:event_type)
      expect(types).to contain_exactly('lead_created', 'lead_contacted', 'lead_qualified')
    end

    it 'only creates lead_created when first_contact_at/qualified_at are absent' do
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1', revenue_contact_id: revenue_contact.id, created_at_source: Time.current)

      described_class.new.perform

      types = account.revenue_events.where(source_system: 'revenue_lead', source_id: lead.id.to_s).pluck(:event_type)
      expect(types).to eq(['lead_created'])
    end
  end

  describe 'deal_created events' do
    it 'creates a deal_created event' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', revenue_contact_id: revenue_contact.id, created_at_source: Time.current)

      described_class.new.perform

      expect(account.revenue_events.find_by(source_system: 'revenue_deal', source_id: deal.id.to_s, event_type: 'deal_created')).to be_present
    end
  end

  describe 'stage events' do
    it 'creates both stage_changed and closed_won for a deal that reached "Cerrado ganado"' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', revenue_contact_id: revenue_contact.id)
      stage_event = account.revenue_stage_events.create!(zoho_deal_id: 'deal-1', revenue_deal_id: deal.id, revenue_contact_id: revenue_contact.id,
                                                         stage: 'Cerrado ganado', previous_stage: 'Apartado', entered_at: Time.current)

      described_class.new.perform

      types = account.revenue_events.where(source_system: 'revenue_stage_event', source_id: stage_event.id.to_s).pluck(:event_type)
      expect(types).to contain_exactly('stage_changed', 'closed_won')
    end

    it 'creates only stage_changed for an intermediate stage with no special classification' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', revenue_contact_id: revenue_contact.id)
      stage_event = account.revenue_stage_events.create!(zoho_deal_id: 'deal-1', revenue_deal_id: deal.id, revenue_contact_id: revenue_contact.id,
                                                         stage: 'Cotizado con visita', entered_at: Time.current)

      described_class.new.perform

      types = account.revenue_events.where(source_system: 'revenue_stage_event', source_id: stage_event.id.to_s).pluck(:event_type)
      expect(types).to eq(['stage_changed'])
    end

    it 'creates visit_effective for a stage in VISITA_EFECTIVA_STAGES' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1', revenue_contact_id: revenue_contact.id)
      stage_event = account.revenue_stage_events.create!(zoho_deal_id: 'deal-1', revenue_deal_id: deal.id, revenue_contact_id: revenue_contact.id,
                                                         stage: 'Qualification', entered_at: Time.current)

      described_class.new.perform

      types = account.revenue_events.where(source_system: 'revenue_stage_event', source_id: stage_event.id.to_s).pluck(:event_type)
      expect(types).to contain_exactly('stage_changed', 'visit_effective')
    end
  end

  describe 'appointment_created events' do
    it 'creates an appointment_created event at starts_at' do
      starts_at = 2.days.from_now
      appointment = account.revenue_appointments.create!(zoho_event_id: 'event-1', revenue_contact_id: revenue_contact.id, starts_at: starts_at)

      described_class.new.perform

      event = account.revenue_events.find_by(source_system: 'revenue_appointment', source_id: appointment.id.to_s)
      expect(event.event_at).to be_within(1.second).of(starts_at)
    end
  end

  describe '#perform' do
    it 'continues with other accounts when one account raises' do
      other_account = create(:account)
      other_account.enable_features!('crm_integration')
      create(:integrations_hook, :zoho_crm, account: other_account, status: 'enabled')
      other_contact = create(:contact, account: other_account)
      other_revenue_contact = other_account.revenue_contacts.create!(chatwoot_contact_id: other_contact.id, first_seen_at: Time.current,
                                                                     last_seen_at: Time.current)
      other_lead = other_account.revenue_leads.create!(zoho_lead_id: 'lead-other', revenue_contact_id: other_revenue_contact.id,
                                                       created_at_source: Time.current)
      allow(RevenueIntelligence::SyncCursorService).to receive(:new).and_wrap_original do |method, acc, sync_type|
        raise 'boom' if acc == account

        method.call(acc, sync_type)
      end

      expect { described_class.new.perform }.not_to raise_error
      expect(other_account.revenue_events.find_by(source_id: other_lead.id.to_s)).to be_present
    end

    it 'only builds events for the given account when an account_id is passed' do
      other_account = create(:account)
      other_account.enable_features!('crm_integration')
      create(:integrations_hook, :zoho_crm, account: other_account, status: 'enabled')
      other_contact = create(:contact, account: other_account)
      other_revenue_contact = other_account.revenue_contacts.create!(chatwoot_contact_id: other_contact.id, first_seen_at: Time.current,
                                                                     last_seen_at: Time.current)
      other_account.revenue_leads.create!(zoho_lead_id: 'lead-other', revenue_contact_id: other_revenue_contact.id, created_at_source: Time.current)
      account.revenue_leads.create!(zoho_lead_id: 'lead-1', revenue_contact_id: revenue_contact.id, created_at_source: Time.current)

      described_class.new.perform(account.id)

      expect(account.revenue_events.where(event_type: 'lead_created')).to exist
      expect(other_account.revenue_events.where(event_type: 'lead_created')).to be_empty
    end
  end
end
