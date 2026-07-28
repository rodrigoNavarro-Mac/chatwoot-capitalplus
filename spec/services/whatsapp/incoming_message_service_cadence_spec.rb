require 'rails_helper'

# El status "failed" de un mensaje de plantilla de cadencia a veces llega recién por este
# webhook asíncrono (Meta acepta el envío en el momento pero la validación del media falla
# después) — ver Cadences::StepExecutor#persist_message y
# Whatsapp::IncomingMessageBaseService#handle_cadence_send_failure. Se usa el servicio de
# 360dialog (estructura de params plana) porque la lógica bajo prueba vive en la clase base
# compartida, no en el parseo del webhook específico del proveedor.
describe Whatsapp::IncomingMessageService do
  let(:account) { create(:account) }
  let!(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:wa_id) { '15551234567' }
  let(:contact) { create(:contact, account: account, phone_number: "+#{wa_id}") }
  let(:contact_inbox) { create(:contact_inbox, inbox: whatsapp_inbox, contact: contact, source_id: wa_id) }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, contact_inbox: contact_inbox, assignee: agent, status: 'open')
  end
  let(:cadence_definition) { create_cadence_definition!(whatsapp_inbox) }
  let(:enrollment) do
    CadenceEnrollment.create!(
      account: account, conversation: conversation, contact: contact, inbox: whatsapp_inbox,
      cadence_definition: cadence_definition, assignee_id: agent.id,
      status: :waiting_response, current_step: 1, steps_snapshot: cadence_steps_snapshot(count: 3)
    )
  end
  let!(:cadence_message) do
    conversation.messages.create!(
      message_type: :outgoing, account_id: account.id, inbox_id: whatsapp_inbox.id,
      content: 'paso 1', source_id: 'wamid.cadence_step1', status: :sent,
      additional_attributes: { cadence_enrollment_id: enrollment.id, cadence_step: 1 }
    )
  end

  def failed_status_params(code: 131_053, title: 'Media upload error')
    {
      'statuses' => [{ 'recipient_id' => wa_id, 'id' => 'wamid.cadence_step1', 'status' => 'failed',
                       'errors' => [{ 'code' => code, 'title' => title }] }]
    }.with_indifferent_access
  end

  before { account.enable_features!(:whatsapp_cadences) }

  it 'schedules a retry for the enrollment when the async failure is transient' do
    expect { described_class.new(inbox: whatsapp_inbox, params: failed_status_params).perform }
      .to have_enqueued_job(Cadences::AdvanceJob).with(enrollment.id)

    enrollment.reload
    expect(enrollment.status).to eq('active')
    expect(enrollment.send_retry_count).to eq(1)
    expect(cadence_message.reload.status).to eq('failed')
  end

  it 'terminates the enrollment when the async failure is permanent' do
    described_class.new(inbox: whatsapp_inbox, params: failed_status_params(code: 132_000, title: 'Template mismatch')).perform

    enrollment.reload
    expect(enrollment.status).to eq('failed')
    expect(enrollment.stopped_reason).to include('132000: Template mismatch')
  end

  it 'does nothing to the enrollment when the message is not the current cadence step' do
    enrollment.update!(current_step: 2)

    described_class.new(inbox: whatsapp_inbox, params: failed_status_params).perform

    expect(enrollment.reload.status).to eq('waiting_response')
  end

  it 'does nothing when the enrollment is no longer waiting_response' do
    enrollment.update!(status: :completed)

    described_class.new(inbox: whatsapp_inbox, params: failed_status_params).perform

    expect(enrollment.reload.status).to eq('completed')
  end

  it 'does not touch unrelated messages without a cadence link' do
    regular_message = conversation.messages.create!(
      message_type: :outgoing, account_id: account.id, inbox_id: whatsapp_inbox.id,
      content: 'hola', source_id: 'wamid.regular', status: :sent
    )
    status_params = {
      'statuses' => [{ 'recipient_id' => wa_id, 'id' => 'wamid.regular', 'status' => 'failed',
                       'errors' => [{ 'code' => 131_053, 'title' => 'Media upload error' }] }]
    }.with_indifferent_access

    expect { described_class.new(inbox: whatsapp_inbox, params: status_params).perform }
      .not_to have_enqueued_job(Cadences::AdvanceJob)

    expect(regular_message.reload.status).to eq('failed')
    expect(enrollment.reload.status).to eq('waiting_response')
  end
end
