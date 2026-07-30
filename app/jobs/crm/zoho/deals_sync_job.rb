# Sincroniza periódicamente el estado del Deal de Zoho vinculado a cada contacto de Chatwoot,
# para que V2::Reports::SalesFunnelBuilder pueda leer "¿tiene deal?"/"¿cerrado ganado?" desde
# datos locales en vez de consultar Zoho en cada carga del reporte. Job de solo lectura sobre
# Zoho: nunca crea ni modifica deals, solo cachea su id/etapa en additional_attributes.external.
class Crm::Zoho::DealsSyncJob < ApplicationJob
  queue_as :scheduled_jobs

  ZOHO_ID_SQL = Arel.sql("additional_attributes -> 'external' ->> 'zoho_id'").freeze

  def perform
    Integrations::Hook.enabled.where(app_id: 'zoho_crm').find_each do |hook|
      sync_hook(hook)
    rescue StandardError => e
      Rails.logger.error "[Crm::Zoho::DealsSyncJob] hook=#{hook.id} error=#{e.message}"
    end
  end

  private

  def sync_hook(hook)
    client = Crm::Zoho::Api::DealsClient.new(hook)

    linked_contact_pairs(hook.account).each_slice(Crm::Zoho::Api::DealsClient::CONTACT_BATCH_SIZE) do |batch|
      sync_batch(client, batch)
    end
  end

  # [[contact_id, zoho_contact_id], ...] — solo contactos ya convertidos a Contact en Zoho, porque
  # un Deal siempre referencia Contact_Name al módulo Contacts, nunca a un Lead directo (ver
  # Api::V1::Accounts::Integrations::ZohoCrmController#create_deal).
  def linked_contact_pairs(account)
    account.contacts
           .where("additional_attributes -> 'external' ->> 'zoho_module' = 'Contacts'")
           .where("additional_attributes -> 'external' ->> 'zoho_id' IS NOT NULL")
           .pluck(:id, ZOHO_ID_SQL)
  end

  def sync_batch(client, batch)
    deals_by_zoho_id = client.deals_by_contact_ids(batch.map(&:last))
    return if deals_by_zoho_id.empty?

    Contact.where(id: batch.map(&:first)).find_each do |contact|
      zoho_contact_id = contact.additional_attributes.dig('external', 'zoho_id')
      apply_deal(contact, deals_by_zoho_id[zoho_contact_id])
    end
  end

  def apply_deal(contact, deal)
    return if deal.blank?

    ext = (contact.additional_attributes || {}).deep_dup
    return if ext.dig('external', 'zoho_deal_id') == deal[:deal_id] && ext.dig('external', 'zoho_deal_stage') == deal[:stage]

    ext['external']['zoho_deal_id']        = deal[:deal_id]
    ext['external']['zoho_deal_stage']     = deal[:stage]
    ext['external']['zoho_deal_synced_at'] = Time.current.iso8601
    contact.update!(additional_attributes: ext)
  end
end
