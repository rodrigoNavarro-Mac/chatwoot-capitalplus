require 'rails_helper'

describe V2::Reports::SalesFunnelBuilder do
  let(:account) { create(:account) }
  let(:agent_bot) { create(:agent_bot, account: account, bot_config: { 'variables' => { 'desarrollo' => 'torre-1' } }) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { whatsapp_channel.inbox }
  let(:params) { { since: 20.days.ago.to_i.to_s, until: Time.current.to_i.to_s } }

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
  end

  def create_lead(zoho_id: SecureRandom.hex, zoho_deal_id: nil, zoho_deal_stage: nil, replied: false, created_at: 10.days.ago, target_inbox: inbox)
    external = { 'zoho_id' => zoho_id, 'zoho_module' => 'Contacts' }
    external['zoho_deal_id'] = zoho_deal_id if zoho_deal_id
    external['zoho_deal_stage'] = zoho_deal_stage if zoho_deal_stage

    contact = create(:contact, account: account, additional_attributes: { 'external' => external })
    conversation = create(:conversation, account: account, inbox: target_inbox, contact: contact)
    conversation.update_column(:created_at, created_at)
    create(:message, account: account, inbox: target_inbox, conversation: conversation, message_type: 'incoming') if replied
    contact
  end

  def stage(rows, stage_name, inbox_id: inbox.id)
    rows.find { |r| r[:inbox_id] == inbox_id }[:stages].find { |s| s[:stage] == stage_name }
  end

  def row_calls(rows, inbox_id: inbox.id)
    rows.find { |r| r[:inbox_id] == inbox_id }[:calls]
  end

  describe '#build' do
    it 'only counts contacts linked to Zoho as leads' do
      create_lead
      unlinked_contact = create(:contact, account: account)
      create(:conversation, account: account, inbox: inbox, contact: unlinked_contact).update_column(:created_at, 5.days.ago)

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'leads')[:count]).to eq(1)
    end

    it 'counts customer_replied only for leads whose conversation has an incoming message' do
      create_lead(replied: true)
      create_lead(replied: false)

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'customer_replied')[:count]).to eq(1)
      expect(stage(rows, 'customer_replied')[:actual_percent]).to eq(50.0)
    end

    it 'counts customer_replied for a lead whose only "reply" is an Aircall voice_call message (no WhatsApp text)' do
      contact = create_lead(replied: false)
      conversation = contact.conversations.first
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: 'incoming', content_type: 'voice_call')

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'customer_replied')[:count]).to eq(1)
    end

    it 'counts customer_replied when the only engagement is an outbound call the customer answered' do
      contact = create_lead(replied: false)
      conversation = contact.conversations.first
      create(:call, conversation: conversation, provider: :aircall, direction: :outgoing, status: 'completed')

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'customer_replied')[:count]).to eq(1)
    end

    it 'does not count customer_replied for an outbound call the customer never answered' do
      contact = create_lead(replied: false)
      conversation = contact.conversations.first
      create(:call, conversation: conversation, provider: :aircall, direction: :outgoing, status: 'no_answer')

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'customer_replied')[:count]).to eq(0)
    end

    it 'counts has_deal only for contacts with a cached zoho_deal_id' do
      create_lead(replied: true, zoho_deal_id: 'deal-1')
      create_lead(replied: true)

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'has_deal')[:count]).to eq(1)
    end

    it 'counts closed_won only for deals whose cached stage is "Closed Won"' do
      create_lead(replied: true, zoho_deal_id: 'deal-1', zoho_deal_stage: 'Closed Won')
      create_lead(replied: true, zoho_deal_id: 'deal-2', zoho_deal_stage: 'Negotiation/Review')

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'closed_won')[:count]).to eq(1)
    end

    it 'counts visita_efectiva for deals cached in any of the post-visit Zoho stages' do
      create_lead(replied: true, zoho_deal_id: 'deal-1', zoho_deal_stage: 'Qualification')
      create_lead(replied: true, zoho_deal_id: 'deal-2', zoho_deal_stage: 'Needs Analysis')
      create_lead(replied: true, zoho_deal_id: 'deal-3', zoho_deal_stage: 'Id. Decision Makers')
      create_lead(replied: true, zoho_deal_id: 'deal-4', zoho_deal_stage: 'Cotizado sin cita')

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'visita_efectiva')[:count]).to eq(3)
    end

    it 'counts visita_efectiva for deals cached with an orphaned legacy stage value from before a Zoho picklist rename' do
      create_lead(replied: true, zoho_deal_id: 'deal-1', zoho_deal_stage: 'Visita efectiva')
      create_lead(replied: true, zoho_deal_id: 'deal-2', zoho_deal_stage: 'Identify Decision Makers')

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'visita_efectiva')[:count]).to eq(2)
    end

    it 'counts a closed_won deal under visita_efectiva too, since closing implies the visit already happened' do
      create_lead(replied: true, zoho_deal_id: 'deal-1', zoho_deal_stage: 'Closed Won')

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'visita_efectiva')[:count]).to eq(1)
      expect(stage(rows, 'closed_won')[:count]).to eq(1)
    end

    it 'computes actual_percent relative to the immediately preceding stage, not to total leads' do
      create_lead(replied: true, zoho_deal_id: 'deal-1', zoho_deal_stage: 'Qualification') # has_deal + visita_efectiva
      create_lead(replied: true, zoho_deal_id: 'deal-2') # has_deal only, no visita
      create_lead(replied: true) # replied only, no deal
      create_lead(replied: false) # leads only

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'leads')[:actual_percent]).to eq(100.0)
      expect(stage(rows, 'customer_replied')[:actual_percent]).to eq(75.0) # 3 de 4 leads
      expect(stage(rows, 'has_deal')[:actual_percent]).to eq(66.67) # 2 de 3 contestados
      expect(stage(rows, 'visita_efectiva')[:actual_percent]).to eq(50.0) # 1 de 2 con deal
      expect(stage(rows, 'closed_won')[:actual_percent]).to eq(0.0) # 0 de 1 visita efectiva
    end

    it "only counts a contact under the inbox of their globally-earliest conversation (their true point of entry)" do
      other_channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      other_bot = create(:agent_bot, account: account, bot_config: { 'variables' => { 'desarrollo' => 'torre-2' } })
      create(:agent_bot_inbox, inbox: other_channel.inbox, agent_bot: other_bot)

      contact = create(:contact, account: account, additional_attributes: { 'external' => { 'zoho_id' => 'z-1', 'zoho_module' => 'Contacts' } })
      first_conversation = create(:conversation, account: account, inbox: other_channel.inbox, contact: contact)
      first_conversation.update_column(:created_at, 15.days.ago)
      later_conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      later_conversation.update_column(:created_at, 5.days.ago)

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'leads')[:count]).to eq(0)
      expect(stage(rows, 'leads', inbox_id: other_channel.inbox.id)[:count]).to eq(1)
    end

    it 'excludes inboxes without a configured desarrollo' do
      undeveloped_channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)

      rows = described_class.new(account: account, params: params).build

      expect(rows.map { |r| r[:inbox_id] }).not_to include(undeveloped_channel.inbox.id)
    end

    it 'filters by inbox_ids when given' do
      other_channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      other_bot = create(:agent_bot, account: account, bot_config: { 'variables' => { 'desarrollo' => 'torre-2' } })
      create(:agent_bot_inbox, inbox: other_channel.inbox, agent_bot: other_bot)

      rows = described_class.new(account: account, params: params.merge(inbox_ids: [inbox.id])).build

      expect(rows.map { |r| r[:inbox_id] }).to eq([inbox.id])
    end

    it 'attaches the monthly goal and delta for the matching development_key/stage' do
      period_month = Time.zone.at(params[:since].to_i).to_date.beginning_of_month
      create(:sales_funnel_goal, account: account, development_key: 'torre-1', stage: 'leads', period_month: period_month, target_percent: 50)
      create_lead

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'leads')[:target_percent]).to eq(50.0)
      expect(stage(rows, 'leads')[:delta]).to eq(50.0)
    end

    it 'keeps using the most recent past goal when there is none for the exact report month' do
      period_month = Time.zone.at(params[:since].to_i).to_date.beginning_of_month
      create(:sales_funnel_goal, account: account, development_key: 'torre-1', stage: 'leads',
                                 period_month: period_month - 2.months, target_percent: 40)
      create_lead

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'leads')[:target_percent]).to eq(40.0)
    end

    it 'uses the newest applicable goal, ignoring any configured for a later month' do
      period_month = Time.zone.at(params[:since].to_i).to_date.beginning_of_month
      create(:sales_funnel_goal, account: account, development_key: 'torre-1', stage: 'leads',
                                 period_month: period_month - 1.month, target_percent: 40)
      create(:sales_funnel_goal, account: account, development_key: 'torre-1', stage: 'leads',
                                 period_month: period_month + 1.month, target_percent: 90)
      create_lead

      rows = described_class.new(account: account, params: params).build

      expect(stage(rows, 'leads')[:target_percent]).to eq(40.0)
    end

    it 'reports total and answered Aircall calls per inbox' do
      contact = create_lead
      conversation = contact.conversations.first
      create(:call, conversation: conversation, provider: :aircall, status: 'completed', started_at: 5.days.ago)
      create(:call, conversation: conversation, provider: :aircall, status: 'no_answer', started_at: 5.days.ago)
      create(:call, conversation: conversation, provider: :twilio, status: 'completed', started_at: 5.days.ago)

      rows = described_class.new(account: account, params: params).build

      expect(row_calls(rows)).to eq(total: 2, answered: 1, answered_percent: 50.0)
    end

    it 'reports zero calls when the inbox has no Aircall calls' do
      create_lead

      rows = described_class.new(account: account, params: params).build

      expect(row_calls(rows)).to eq(total: 0, answered: 0, answered_percent: 0.0)
    end

    describe 'deal activity outside the new-leads cohort' do
      def stub_deals_for_period(deals)
        fake_service = instance_double(Crm::Zoho::DealsForPeriodService, fetch: deals)
        allow(Crm::Zoho::DealsForPeriodService).to receive(:new).and_return(fake_service)
      end

      # Contacto cuya conversacion cae FUERA del rango del reporte -- nunca cuenta como "lead" de
      # esta cohorte, pero su deal (por zoho_deal_id) si puede coincidir con uno devuelto por
      # Crm::Zoho::DealsForPeriodService (deals creados EN el periodo, sin importar la cohorte).
      def create_old_contact_with_deal(zoho_deal_id:)
        contact = create(:contact, account: account,
                                    additional_attributes: { 'external' => { 'zoho_id' => SecureRandom.hex, 'zoho_deal_id' => zoho_deal_id } })
        create(:conversation, account: account, inbox: inbox, contact: contact).update_column(:created_at, 60.days.ago)
        contact
      end

      it 'adds a deal created this period from a lead outside the cohort to has_deal count/percent' do
        create_lead(replied: true, zoho_deal_id: 'deal-1') # cohorte: 1 lead, 1 con deal
        create_old_contact_with_deal(zoho_deal_id: 'deal-99')
        stub_deals_for_period([{ 'id' => 'deal-99', 'Stage' => 'Negotiation/Review' }])

        rows = described_class.new(account: account, params: params).build

        expect(stage(rows, 'has_deal')[:count]).to eq(2)
        expect(stage(rows, 'has_deal')[:activity_count]).to eq(1)
        expect(stage(rows, 'has_deal')[:actual_percent]).to eq(200.0) # 2 de 1 contestado -- puede pasar de 100%
      end

      it 'does not double count a deal that already belongs to the cohort' do
        create_lead(replied: true, zoho_deal_id: 'deal-1')
        stub_deals_for_period([{ 'id' => 'deal-1', 'Stage' => 'Qualification' }])

        rows = described_class.new(account: account, params: params).build

        expect(stage(rows, 'has_deal')[:count]).to eq(1)
        expect(stage(rows, 'has_deal')[:activity_count]).to eq(0)
      end

      it 'cascades activity into visita_efectiva and closed_won when the outside deal is already in a later stage' do
        create_old_contact_with_deal(zoho_deal_id: 'deal-77')
        stub_deals_for_period([{ 'id' => 'deal-77', 'Stage' => 'Closed Won' }])

        rows = described_class.new(account: account, params: params).build

        expect(stage(rows, 'has_deal')[:activity_count]).to eq(1)
        expect(stage(rows, 'visita_efectiva')[:activity_count]).to eq(1)
        expect(stage(rows, 'closed_won')[:activity_count]).to eq(1)
      end

      it 'has a nil activity_count for leads and customer_replied, which have no deal-activity equivalent' do
        create_lead(replied: true, zoho_deal_id: 'deal-1')
        stub_deals_for_period([])

        rows = described_class.new(account: account, params: params).build

        expect(stage(rows, 'leads')[:activity_count]).to be_nil
        expect(stage(rows, 'customer_replied')[:activity_count]).to be_nil
      end

      # Caso real detectado 2026-08-25: un lead creado en Zoho meses antes (via Meta Ads, nunca
      # escribio por WhatsApp) que recien genero un deal -- Crm::Zoho::DealsSyncJob solo actualiza
      # contactos que YA existen en Chatwoot, asi que ese deal no tiene con que vincularse.
      it 'counts a deal with no Chatwoot contact at all as external, separate from activity' do
        create_lead(replied: true, zoho_deal_id: 'deal-1') # cohorte: 1 lead, 1 con deal
        stub_deals_for_period([{ 'id' => 'deal-no-contact', 'Stage' => 'Negotiation/Review' }])

        rows = described_class.new(account: account, params: params).build

        expect(stage(rows, 'has_deal')[:count]).to eq(2)
        expect(stage(rows, 'has_deal')[:activity_count]).to eq(0)
        expect(stage(rows, 'has_deal')[:external_count]).to eq(1)
      end

      it 'cascades external into visita_efectiva and closed_won when the unlinked deal is already in a later stage' do
        stub_deals_for_period([{ 'id' => 'deal-no-contact', 'Stage' => 'Closed Won' }])

        rows = described_class.new(account: account, params: params).build

        expect(stage(rows, 'has_deal')[:external_count]).to eq(1)
        expect(stage(rows, 'visita_efectiva')[:external_count]).to eq(1)
        expect(stage(rows, 'closed_won')[:external_count]).to eq(1)
      end

      it 'has a nil external_count for leads and customer_replied' do
        stub_deals_for_period([])

        rows = described_class.new(account: account, params: params).build

        expect(stage(rows, 'leads')[:external_count]).to be_nil
        expect(stage(rows, 'customer_replied')[:external_count]).to be_nil
      end
    end
  end
end
