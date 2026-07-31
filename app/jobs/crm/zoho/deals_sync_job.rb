# Sincroniza periódicamente el estado del Deal de Zoho vinculado a cada contacto de Chatwoot,
# para que V2::Reports::SalesFunnelBuilder pueda leer "¿tiene deal?"/"¿cerrado ganado?" desde
# datos locales en vez de consultar Zoho en cada carga del reporte. Job de solo lectura sobre
# Zoho: nunca crea ni modifica deals, solo cachea su id/etapa en additional_attributes.external.
#
# Busca por teléfono/email (ver Crm::Zoho::Api::DealsClient) en vez de filtrar contactos por
# additional_attributes.external.zoho_module — ese campo no se actualiza cuando el Lead se
# convierte a Contact directamente en Zoho, así que no sirve para decidir quién es candidato.
class Crm::Zoho::DealsSyncJob < ApplicationJob
  queue_as :scheduled_jobs

  # DealsClient hace hasta 2 llamadas HTTP por contacto (resuelve el Contact en Zoho, luego
  # busca su Deal — ver el comentario en DealsClient sobre por qué no se puede usar COQL en
  # lote). Se procesa en tandas para no acumular una sola corrida gigante de requests.
  BATCH_SIZE = 50

  # account_id: si se pasa, sincroniza solo esa cuenta (botón "Sincronizar ahora" del reporte);
  # si se omite, sincroniza todas las cuentas con Zoho CRM habilitado (corrida del cron).
  def perform(account_id = nil)
    hooks = Integrations::Hook.enabled.where(app_id: 'zoho_crm')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      sync_hook(hook)
    rescue StandardError => e
      Rails.logger.error "[Crm::Zoho::DealsSyncJob] hook=#{hook.id} error=#{e.message}"
    end
  end

  private

  def sync_hook(hook)
    client = Crm::Zoho::Api::DealsClient.new(hook)

    linked_contacts(hook.account).each_slice(BATCH_SIZE) do |batch|
      sync_batch(client, batch)
    end
  end

  # Cualquier contacto con algún vínculo a Zoho (Lead o Contact) es candidato a tener deal.
  def linked_contacts(account)
    account.contacts
           .where("additional_attributes -> 'external' ->> 'zoho_id' IS NOT NULL")
           .pluck(:id, :phone_number, :email)
  end

  def sync_batch(client, batch)
    contacts = batch.map { |id, phone, email| { id: id, phone: phone, email: email } }
    deals_by_contact_id = client.deals_for_contacts(contacts)
    return if deals_by_contact_id.empty?

    Contact.where(id: deals_by_contact_id.keys).find_each do |contact|
      apply_deal(contact, deals_by_contact_id[contact.id])
    end
  end

  def apply_deal(contact, deal)
    return if deal.blank?

    ext = (contact.additional_attributes || {}).deep_dup
    ext['external'] ||= {}
    return if ext['external']['zoho_deal_id'] == deal[:deal_id] && ext['external']['zoho_deal_stage'] == deal[:stage]

    ext['external']['zoho_deal_id']        = deal[:deal_id]
    ext['external']['zoho_deal_stage']     = deal[:stage]
    ext['external']['zoho_deal_synced_at'] = Time.current.iso8601
    contact.update!(additional_attributes: ext)
  end
end
