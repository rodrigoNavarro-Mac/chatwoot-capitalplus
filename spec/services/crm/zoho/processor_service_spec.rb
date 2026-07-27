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

    context 'when the Lead already has First_Contact_Time set' do
      before do
        existing_record = { 'First_Contact_Time' => '2026-01-01T10:00:00-06:00' }
        allow(finder).to receive(:find_or_create).with(contact)
                                                 .and_return(zoho_id: 'l1', zoho_module: 'Leads', record: existing_record)
        allow(leads_client).to receive(:update)
      end

      it 'does not overwrite the existing value' do
        service.handle_first_reply_created(event_data)
        expect(leads_client).not_to have_received(:update)
      end
    end

    context 'when the Lead has no First_Contact_Time yet' do
      before do
        conversation.update!(first_reply_created_at: Time.zone.parse('2026-07-27T10:15:30-06:00'))
        allow(finder).to receive(:find_or_create).with(contact)
                                                 .and_return(zoho_id: 'l1', zoho_module: 'Leads', record: { 'First_Contact_Time' => nil })
        allow(leads_client).to receive(:update)
      end

      it 'updates First_Contact_Time with the first reply timestamp' do
        service.handle_first_reply_created(event_data)
        expect(leads_client).to have_received(:update)
          .with('l1', { 'First_Contact_Time' => conversation.reload.first_reply_created_at.iso8601 })
      end
    end

    context 'when the finder result has no cached record' do
      before do
        conversation.update!(first_reply_created_at: Time.zone.parse('2026-07-27T10:15:30-06:00'))
        allow(finder).to receive(:find_or_create).with(contact).and_return(zoho_id: 'l1', zoho_module: 'Leads')
        allow(finder).to receive(:fetch_record).with(contact).and_return({})
        allow(leads_client).to receive(:update)
      end

      it 'fetches the record before updating' do
        service.handle_first_reply_created(event_data)
        expect(finder).to have_received(:fetch_record).with(contact)
        expect(leads_client).to have_received(:update)
          .with('l1', { 'First_Contact_Time' => conversation.reload.first_reply_created_at.iso8601 })
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
end
