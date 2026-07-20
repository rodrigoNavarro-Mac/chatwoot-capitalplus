# Crea un Task en Zoho CRM cuando la cadencia genera un CadenceCallTask (llamada pendiente sin
# respuesta al WhatsApp), para que quede visible en Zoho además de la notificación in-app de
# Chatwoot. No participa del flujo de la cadencia: si Zoho no está conectado o falla, se registra
# el error y se sigue de largo — nunca bloquea ni pausa el enrollment.
class Crm::Zoho::CallTaskSyncService
  def initialize(cadence_call_task)
    @call_task = cadence_call_task
    @conversation = cadence_call_task.conversation
    @contact = @conversation.contact
    @account = cadence_call_task.account
  end

  def call
    return if zoho_hook.blank? || @contact.blank?

    result = Crm::Zoho::ContactFinderService.new(zoho_hook).find_or_create(@contact)
    tasks_client.create(
      zoho_id: result[:zoho_id],
      zoho_module: result[:zoho_module],
      subject: subject,
      details: {
        due_date: Date.current,
        owner_email: @call_task.user&.email,
        description: Crm::Zoho::Mappers::ConversationMapper.conversation_note(@conversation)
      }
    )
  rescue StandardError => e
    Rails.logger.error("[Crm::Zoho::CallTaskSyncService] failed for cadence_call_task=#{@call_task.id}: #{e.message}")
  end

  private

  def zoho_hook
    @zoho_hook ||= Integrations::Hook.find_by(account: @account, app_id: 'zoho_crm', status: 'enabled')
  end

  def tasks_client
    @tasks_client ||= Crm::Zoho::Api::TasksClient.new(zoho_hook)
  end

  def subject
    "Llamar a #{@contact.name.presence || @contact.phone_number} — cadencia paso #{@call_task.step} (conversación ##{@conversation.display_id})"
  end
end
