require 'rails_helper'

describe Crm::Zoho::CallTaskSyncService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent, email: 'agent@example.com') }
  let(:contact) { create(:contact, account: account, name: 'Juan Perez', phone_number: '+15551234567') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, assignee: agent, status: 'open')
  end
  let(:cadence_definition) { create_cadence_definition!(whatsapp_inbox) }
  let(:enrollment) do
    CadenceEnrollment.create!(
      account: account, conversation: conversation, contact: contact, inbox: whatsapp_inbox,
      cadence_definition: cadence_definition, assignee_id: agent.id,
      status: :pending_agent_call, current_step: 1, steps_snapshot: cadence_steps_snapshot(count: 3)
    )
  end
  let(:call_task) do
    CadenceCallTask.create!(account: account, cadence_enrollment: enrollment, conversation: conversation, user: agent, step: 1)
  end

  describe '#call' do
    it 'does nothing when Zoho CRM is not connected' do
      expect(Crm::Zoho::Api::TasksClient).not_to receive(:new)

      described_class.new(call_task).call
    end

    context 'when Zoho CRM is connected' do
      before do
        account.enable_features!('crm_integration')
        create(
          :integrations_hook, account: account, app_id: 'zoho_crm', status: 'enabled',
                              settings: { client_id: 'x', client_secret: 'y', refresh_token: 'z' }
        )
      end

      # rubocop:disable RSpec/AnyInstance -- same rationale as razon_compra_resolver_spec.rb:
      # ContactFinderService/TasksClient are instantiated internally, no injection seam without
      # adding a parameter that only exists for testing.
      it 'creates a Zoho task linked to the lead, owned by the assigned agent, and not for other statuses' do
        allow_any_instance_of(Crm::Zoho::ContactFinderService).to receive(:find_or_create)
          .and_return({ zoho_id: 'zoho-123', zoho_module: 'Leads' })

        expect_any_instance_of(Crm::Zoho::Api::TasksClient).to receive(:create).with(
          zoho_id: 'zoho-123',
          zoho_module: 'Leads',
          subject: a_string_including('Juan Perez'),
          details: {
            due_date: Date.current,
            owner_email: 'agent@example.com',
            description: a_kind_of(String)
          }
        )

        described_class.new(call_task).call
      end

      it 'does not raise when the Zoho API call fails' do
        allow_any_instance_of(Crm::Zoho::ContactFinderService).to receive(:find_or_create).and_raise(StandardError, 'boom')

        expect { described_class.new(call_task).call }.not_to raise_error
      end

      it 'skips the Owner field when the call task has no agent' do
        call_task.update!(user: nil)
        allow_any_instance_of(Crm::Zoho::ContactFinderService).to receive(:find_or_create)
          .and_return({ zoho_id: 'zoho-123', zoho_module: 'Leads' })

        expect_any_instance_of(Crm::Zoho::Api::TasksClient).to receive(:create)
          .with(hash_including(details: hash_including(owner_email: nil)))

        described_class.new(call_task).call
      end
      # rubocop:enable RSpec/AnyInstance
    end
  end
end
