require 'rails_helper'

RSpec.describe Crm::Zoho::ProcessorService do
  let(:account) { create(:account) }
  let(:hook) { create(:integrations_hook, :zoho_crm, account: account) }
  let(:contact) { create(:contact, account: account, email: 'test@example.com', phone_number: '+1234567890') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: :outgoing) }
  let(:service) { described_class.new(hook) }
  let(:finder) { instance_double(Crm::Zoho::ContactFinderService) }
  let(:leads_client) { instance_double(Crm::Zoho::Api::LeadsClient) }
  let(:contacts_client) { instance_double(Crm::Zoho::Api::ContactsClient) }
  let(:notes_client) { instance_double(Crm::Zoho::Api::NotesClient) }

  before do
    account.enable_features('crm_integration')
    allow(Crm::Zoho::ContactFinderService).to receive(:new).and_return(finder)
    allow(Crm::Zoho::Api::LeadsClient).to receive(:new).and_return(leads_client)
    allow(Crm::Zoho::Api::ContactsClient).to receive(:new).and_return(contacts_client)
    allow(Crm::Zoho::Api::NotesClient).to receive(:new).and_return(notes_client)
  end

  describe '#handle_first_reply_created' do
    let(:event_data) { { conversation: conversation, message: message } }

    context 'when contact is not identifiable' do
      before do
        contact.update!(email: nil, phone_number: nil)
        allow(finder).to receive(:find_or_create)
      end

      it 'does not call Zoho' do
        service.handle_first_reply_created(event_data)
        expect(finder).not_to have_received(:find_or_create)
      end
    end

    context 'when the linked record is a Contact instead of a Lead' do
      before do
        allow(finder).to receive(:find_or_create).with(contact).and_return(zoho_id: 'c1', zoho_module: 'Contacts')
        allow(leads_client).to receive(:update)
      end

      it 'skips the update' do
        service.handle_first_reply_created(event_data)
        expect(leads_client).not_to have_received(:update)
      end
    end

    context 'when the Lead already has both fields set' do
      before do
        existing_record = { 'First_Contact_Time' => '2026-01-01T10:00:00-06:00', 'Tiempo_de_respuesta_inicial' => 5 }
        allow(finder).to receive(:find_or_create).with(contact)
                                                 .and_return(zoho_id: 'l1', zoho_module: 'Leads', record: existing_record)
        allow(leads_client).to receive(:update)
      end

      it 'does not overwrite the existing values' do
        service.handle_first_reply_created(event_data)
        expect(leads_client).not_to have_received(:update)
      end
    end

    context 'when neither field is set on the Lead yet' do
      before do
        conversation.update!(created_at: Time.zone.parse('2026-07-27T10:00:00-06:00'),
                             first_reply_created_at: Time.zone.parse('2026-07-27T10:03:30-06:00'))
        allow(finder).to receive(:find_or_create).with(contact)
                                                 .and_return(zoho_id: 'l1', zoho_module: 'Leads',
                                                             record: { 'First_Contact_Time' => nil, 'Tiempo_de_respuesta_inicial' => nil })
        allow(leads_client).to receive(:update)
      end

      it 'sends First_Contact_Time and Tiempo_de_respuesta_inicial (rounded minutes) in a single update' do
        service.handle_first_reply_created(event_data)
        expect(leads_client).to have_received(:update)
          .with('l1', { 'First_Contact_Time' => conversation.reload.first_reply_created_at.iso8601, 'Tiempo_de_respuesta_inicial' => 4 })
      end
    end

    context 'when only Tiempo_de_respuesta_inicial is missing' do
      before do
        conversation.update!(created_at: Time.zone.parse('2026-07-27T10:00:00-06:00'),
                             first_reply_created_at: Time.zone.parse('2026-07-27T10:15:30-06:00'))
        existing_record = { 'First_Contact_Time' => '2026-01-01T00:00:00-06:00', 'Tiempo_de_respuesta_inicial' => nil }
        allow(finder).to receive(:find_or_create).with(contact)
                                                 .and_return(zoho_id: 'l1', zoho_module: 'Leads', record: existing_record)
        allow(leads_client).to receive(:update)
      end

      it 'sends only Tiempo_de_respuesta_inicial' do
        service.handle_first_reply_created(event_data)
        expect(leads_client).to have_received(:update).with('l1', { 'Tiempo_de_respuesta_inicial' => 16 })
      end
    end

    context 'when only First_Contact_Time is missing' do
      before do
        conversation.update!(first_reply_created_at: Time.zone.parse('2026-07-27T10:15:30-06:00'))
        allow(finder).to receive(:find_or_create).with(contact)
                                                 .and_return(zoho_id: 'l1', zoho_module: 'Leads',
                                                             record: { 'First_Contact_Time' => nil, 'Tiempo_de_respuesta_inicial' => 3 })
        allow(leads_client).to receive(:update)
      end

      it 'sends only First_Contact_Time' do
        service.handle_first_reply_created(event_data)
        expect(leads_client).to have_received(:update)
          .with('l1', { 'First_Contact_Time' => conversation.reload.first_reply_created_at.iso8601 })
      end
    end

    context 'when a bot handled the conversation before the human reply' do
      before do
        conversation.update!(created_at: Time.zone.parse('2026-07-27T09:00:00-06:00'))
        handoff_time = Time.zone.parse('2026-07-27T10:00:00-06:00')
        create(
          :reporting_event,
          name: 'conversation_bot_handoff',
          account: account,
          inbox: conversation.inbox,
          conversation: conversation,
          event_start_time: conversation.created_at,
          event_end_time: handoff_time
        )
        conversation.update!(first_reply_created_at: handoff_time + 90.seconds)
        allow(finder).to receive(:find_or_create).with(contact)
                                                 .and_return(zoho_id: 'l1', zoho_module: 'Leads', record: {})
        allow(leads_client).to receive(:update)
      end

      it 'measures the response time from the bot handoff, not from the conversation start, rounded to the nearest minute' do
        service.handle_first_reply_created(event_data)
        expect(leads_client).to have_received(:update)
          .with('l1', hash_including('Tiempo_de_respuesta_inicial' => 2))
      end
    end

    context 'when the finder result has no cached record' do
      before do
        conversation.update!(created_at: Time.zone.parse('2026-07-27T10:00:00-06:00'),
                             first_reply_created_at: Time.zone.parse('2026-07-27T10:15:30-06:00'))
        allow(finder).to receive(:find_or_create).with(contact).and_return(zoho_id: 'l1', zoho_module: 'Leads')
        allow(finder).to receive(:fetch_record).with(contact).and_return({})
        allow(leads_client).to receive(:update)
      end

      it 'fetches the record before updating' do
        service.handle_first_reply_created(event_data)
        expect(finder).to have_received(:fetch_record).with(contact)
        expect(leads_client).to have_received(:update)
          .with('l1', { 'First_Contact_Time' => conversation.reload.first_reply_created_at.iso8601, 'Tiempo_de_respuesta_inicial' => 16 })
      end
    end

    context 'when the Zoho API raises an error' do
      before do
        conversation.update!(first_reply_created_at: Time.zone.now)
        allow(finder).to receive(:find_or_create).with(contact)
                                                 .and_return(zoho_id: 'l1', zoho_module: 'Leads', record: {})
        allow(leads_client).to receive(:update).and_raise(Crm::Zoho::Api::BaseClient::ApiError.new('API Error'))
        allow(Rails.logger).to receive(:error)
        allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: nil))
      end

      it 'logs the error without raising' do
        expect { service.handle_first_reply_created(event_data) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(/ZOHO CRM.*handle_first_reply_created/)
      end
    end
  end

  describe '#handle_message_created' do
    let(:agent) { create(:user, account: account) }
    let(:agent_message) do
      create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: agent,
                       created_at: Time.zone.parse('2026-07-27T10:15:30-06:00'))
    end
    let(:event_data) { { message: agent_message } }

    context 'when the message is a human agent reply' do
      before do
        allow(finder).to receive(:find_or_create).with(contact).and_return(zoho_id: 'l1', zoho_module: 'Leads')
        allow(leads_client).to receive(:update)
      end

      it 'updates Ultimo_conctacto on the Lead with the message timestamp' do
        service.handle_message_created(event_data)
        expect(leads_client).to have_received(:update).with('l1', { 'Ultimo_conctacto' => agent_message.created_at.iso8601 })
      end
    end

    context 'when the linked record is a Contact instead of a Lead' do
      before do
        allow(finder).to receive(:find_or_create).with(contact).and_return(zoho_id: 'c1', zoho_module: 'Contacts')
        allow(contacts_client).to receive(:update)
      end

      it 'updates Ultimo_conctacto on the Contact' do
        service.handle_message_created(event_data)
        expect(contacts_client).to have_received(:update).with('c1', { 'Ultimo_conctacto' => agent_message.created_at.iso8601 })
      end
    end

    context 'when the message is a private note' do
      before do
        agent_message.update!(private: true)
        allow(finder).to receive(:find_or_create)
      end

      it 'does not call Zoho' do
        service.handle_message_created(event_data)
        expect(finder).not_to have_received(:find_or_create)
      end
    end

    context 'when the message is incoming from the contact' do
      let(:agent_message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }

      before { allow(finder).to receive(:find_or_create) }

      it 'does not call Zoho' do
        service.handle_message_created(event_data)
        expect(finder).not_to have_received(:find_or_create)
      end
    end

    context 'when the message is a bot response' do
      let(:agent_message) do
        create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: create(:agent_bot))
      end

      before { allow(finder).to receive(:find_or_create) }

      it 'does not call Zoho' do
        service.handle_message_created(event_data)
        expect(finder).not_to have_received(:find_or_create)
      end
    end

    context 'when contact is not identifiable' do
      before do
        contact.update!(email: nil, phone_number: nil)
        allow(finder).to receive(:find_or_create)
      end

      it 'does not call Zoho' do
        service.handle_message_created(event_data)
        expect(finder).not_to have_received(:find_or_create)
      end
    end

    context 'when the Zoho API raises an error' do
      before do
        allow(finder).to receive(:find_or_create).with(contact).and_return(zoho_id: 'l1', zoho_module: 'Leads')
        allow(leads_client).to receive(:update).and_raise(Crm::Zoho::Api::BaseClient::ApiError.new('API Error'))
        allow(Rails.logger).to receive(:error)
        allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: nil))
      end

      it 'logs the error without raising' do
        expect { service.handle_message_created(event_data) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(/ZOHO CRM.*handle_message_created/)
      end
    end
  end
end
