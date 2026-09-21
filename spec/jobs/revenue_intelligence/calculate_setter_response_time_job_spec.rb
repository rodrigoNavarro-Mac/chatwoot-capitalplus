require 'rails_helper'

describe RevenueIntelligence::CalculateSetterResponseTimeJob do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp_channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let!(:revenue_contact) do
    account.revenue_contacts.create!(chatwoot_contact_id: contact.id, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  before do
    account.enable_features!('crm_integration')
    create(:integrations_hook, :zoho_crm, account: account, status: 'enabled')
  end

  def create_lead(**attrs)
    account.revenue_leads.create!({ zoho_lead_id: 'lead-1', revenue_contact_id: revenue_contact.id,
                                    created_at_source: 2.days.ago }.merge(attrs))
  end

  it 'sets first_human_contact_at/channel/business_seconds from the earliest human WhatsApp message' do
    lead = create_lead
    create(:message, account: account, conversation: conversation, message_type: 'outgoing', created_at: 1.day.ago)

    described_class.new.perform

    lead.reload
    expect(lead.first_human_contact_channel).to eq('whatsapp_message')
    expect(lead.first_human_contact_at).to be_present
    expect(lead.first_human_response_seconds).to be_present
    expect(lead.first_human_response_business_seconds).to be_present
  end

  it 'never counts a bot/automated message as the human contact (Message#human_response? gate)' do
    lead = create_lead
    create(:message, :bot_message, account: account, conversation: conversation, created_at: 1.day.ago)

    described_class.new.perform

    expect(lead.reload.first_human_contact_at).to be_nil
  end

  it 'never counts an outgoing message that carries an automation_rule_id as the human contact' do
    lead = create_lead
    create(:message, account: account, conversation: conversation, message_type: 'outgoing', created_at: 1.day.ago,
                     content_attributes: { automation_rule_id: 42 })

    described_class.new.perform

    expect(lead.reload.first_human_contact_at).to be_nil
  end

  it 'sets first_human_contact_channel to "call" from a real connected outgoing call' do
    lead = create_lead
    create(:call, account: account, conversation: conversation, contact: contact, direction: :outgoing, status: 'completed',
                  started_at: 1.day.ago)

    described_class.new.perform

    expect(lead.reload.first_human_contact_channel).to eq('call')
  end

  it 'counts an incoming call as human contact only when an agent actually accepted it' do
    agent = create(:user, account: account)
    lead = create_lead
    create(:call, account: account, conversation: conversation, contact: contact, direction: :incoming, status: 'completed',
                  started_at: 1.day.ago, accepted_by_agent_id: agent.id)

    described_class.new.perform

    expect(lead.reload.first_human_contact_channel).to eq('call')
  end

  it 'never counts an unanswered/failed/rejected call, or an incoming call nobody picked up (voicemail), as human contact' do
    lead = create_lead
    create(:call, account: account, conversation: conversation, contact: contact, direction: :incoming, status: 'no_answer',
                  started_at: 1.day.ago)

    described_class.new.perform

    expect(lead.reload.first_human_contact_at).to be_nil
  end

  it 'picks whichever of message/call actually happened earliest' do
    lead = create_lead
    create(:message, account: account, conversation: conversation, message_type: 'outgoing', created_at: 12.hours.ago)
    create(:call, account: account, conversation: conversation, contact: contact, direction: :outgoing, status: 'completed',
                  started_at: 20.hours.ago)

    described_class.new.perform

    expect(lead.reload.first_human_contact_channel).to eq('call')
  end

  it 'skips leads without a resolved Chatwoot identity (revenue_contact_id nil) -- known coverage limitation' do
    lead = account.revenue_leads.create!(zoho_lead_id: 'lead-2', created_at_source: 2.days.ago)
    create(:message, account: account, conversation: conversation, message_type: 'outgoing', created_at: 1.day.ago)

    described_class.new.perform

    expect(lead.reload.first_human_contact_at).to be_nil
  end

  it 'leaves a lead with no trackable human response untouched (pending, never imputed)' do
    lead = create_lead

    described_class.new.perform

    expect(lead.reload.first_human_contact_at).to be_nil
  end

  it 'never recomputes a lead that already has first_human_contact_at set' do
    original_time = 3.days.ago
    lead = create_lead(first_human_contact_at: original_time, first_human_contact_channel: 'call', first_human_response_seconds: 10,
                       first_human_response_business_seconds: 10)
    create(:message, account: account, conversation: conversation, message_type: 'outgoing', created_at: 1.hour.ago)

    described_class.new.perform

    expect(lead.reload.first_human_contact_channel).to eq('call')
  end
end
