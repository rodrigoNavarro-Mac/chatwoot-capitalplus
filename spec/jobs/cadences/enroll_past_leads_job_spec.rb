require 'rails_helper'

describe Cadences::EnrollPastLeadsJob do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:other_whatsapp_channel) do
    create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false, phone_number: '+15559990000')
  end
  let(:other_whatsapp_inbox) { other_whatsapp_channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:other_contact) { create(:contact, account: account, phone_number: '+15557654321') }

  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, assignee: agent, status: 'open')
  end
  let(:other_inbox_conversation) do
    create(:conversation, account: account, inbox: other_whatsapp_inbox, contact: other_contact, assignee: agent, status: 'open')
  end

  before do
    account.enable_features!(:whatsapp_cadences)
    create_cadence_steps!(whatsapp_inbox)
    create_cadence_steps!(other_whatsapp_inbox)
  end

  # Cadences::PastLeadEnrollmentService (lo que este job usa por debajo) solo engancha
  # conversaciones que YA recibieron una plantilla que matchea un paso configurado — mismo
  # criterio que el rake task cadences:enroll_past_leads que este botón reemplaza en el UI.
  def send_template_message(conversation, inbox, name: 'cadencia_paso_1', language: 'es_MX')
    create(:message, conversation: conversation, account: account, inbox: inbox,
                     message_type: :outgoing, created_at: 2.days.ago,
                     additional_attributes: { template_params: { 'name' => name, 'language' => language } })
  end

  it 'enrolls eligible conversations across all inboxes of the account when no inbox_id is given' do
    send_template_message(conversation, whatsapp_inbox)
    send_template_message(other_inbox_conversation, other_whatsapp_inbox)

    expect { described_class.new.perform(account.id) }.to change(CadenceEnrollment, :count).by(2)
  end

  it 'scopes to a single inbox when inbox_id is given' do
    send_template_message(conversation, whatsapp_inbox)
    send_template_message(other_inbox_conversation, other_whatsapp_inbox)

    expect { described_class.new.perform(account.id, inbox_id: whatsapp_inbox.id) }.to change(CadenceEnrollment, :count).by(1)
    expect(CadenceEnrollment.pluck(:conversation_id)).to contain_exactly(conversation.id)
  end

  it 'skips conversations with no template ever sent (nothing to resume from)' do
    conversation

    expect { described_class.new.perform(account.id) }.not_to change(CadenceEnrollment, :count)
  end

  # Reproduce el caso real: un lead recibio una plantilla fuera de la cadencia (ej. el
  # disparador inicial de Zoho, antes de que existiera una CadenceDefinition activa) cuyo
  # nombre no coincide con ningun paso configurado. PastLeadEnrollmentService por si solo lo
  # deja en no_matching_step y nunca lo engancha; este job debe caer a un enrollment fresco en
  # el paso 0 en vez de dejarlo fuera para siempre.
  it 'falls back to a fresh step-0 enrollment when the previously sent template matches no configured step' do
    send_template_message(conversation, whatsapp_inbox, name: 'plantilla_inicial_formulario_fuego')

    expect { described_class.new.perform(account.id) }.to change(CadenceEnrollment, :count).by(1)

    enrollment = CadenceEnrollment.find_by(conversation_id: conversation.id)
    expect(enrollment.status).to eq('active')
    expect(enrollment.current_step).to eq(0)
  end

  it 'skips conversations that are already enrolled' do
    send_template_message(conversation, whatsapp_inbox)
    Cadences::EnrollmentService.new(conversation: conversation).enroll!

    expect { described_class.new.perform(account.id) }.not_to change(CadenceEnrollment, :count)
  end

  it 'does not enroll conversations from another account' do
    send_template_message(conversation, whatsapp_inbox)
    other_account = create(:account)
    other_account.enable_features!(:whatsapp_cadences)
    other_account_channel = create(:channel_whatsapp, account: other_account, validate_provider_config: false, sync_templates: false)
    create_cadence_steps!(other_account_channel.inbox)
    other_account_contact = create(:contact, account: other_account, phone_number: '+15551112222')
    other_account_conversation = create(:conversation, account: other_account, inbox: other_account_channel.inbox, contact: other_account_contact,
                                                       status: 'open')
    create(:message, conversation: other_account_conversation, account: other_account, inbox: other_account_channel.inbox,
                     message_type: :outgoing, created_at: 2.days.ago,
                     additional_attributes: { template_params: { 'name' => 'cadencia_paso_1', 'language' => 'es_MX' } })

    expect { described_class.new.perform(account.id) }.to change(CadenceEnrollment, :count).by(1)
    expect(CadenceEnrollment.exists?(conversation_id: other_account_conversation.id)).to be(false)
  end

  it 'does nothing for an unknown account_id' do
    expect { described_class.new.perform(-1) }.not_to raise_error
  end
end
