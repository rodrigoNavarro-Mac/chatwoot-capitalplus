# Backfill de additional_attributes.external.zoho_created_at para contactos que ya tienen zoho_id
# vinculado pero nunca cachearon el Created_Time real del lead/contacto de Zoho (contactos
# vinculados antes de que Crm::Zoho::ContactFinderService empezara a guardarlo) — necesario para
# que V2::Reports::SalesFunnelBuilder distinga leads nuevos de leads reactivados
# (#partition_new_vs_reactivated). Caso real que motivó esto: campaña de reactivación a leads viejos
# vía CSV contaba como "leads nuevos de agosto" en el embudo, aunque los leads reales de Zoho
# llevaran meses (detectado 2026-09-03: 278 vs 211 leads de un desarrollo).
#
# Idempotente por diseño: #pending_contacts solo trae los que aún no tienen zoho_created_at, así que
# correr #perform varias veces (ej. para reintentar los que fallaron por rate limit) no repite
# trabajo ya hecho.
class Crm::Zoho::LeadCreatedAtBackfillService
  RATE_LIMIT_DELAY = 0.3 # segundos entre llamadas a la API de Zoho

  def initialize(account)
    @account = account
  end

  def pending_contacts
    return Contact.none if hook.blank?

    account.contacts
           .where("additional_attributes -> 'external' ->> 'zoho_id' IS NOT NULL")
           .where("additional_attributes -> 'external' ->> 'zoho_created_at' IS NULL")
  end

  # { updated:, relinked:, not_found:, errored: } — relinked es un subconjunto de updated (ver
  # #resolve_record). not_found queda sin zoho_created_at y se sigue tratando como "nuevo" (ver
  # SalesFunnelBuilder), errored se puede reintentar corriendo el backfill de nuevo (ej. si fue un
  # rate limit o timeout puntual de Zoho).
  def perform
    stats = { updated: 0, relinked: 0, not_found: 0, errored: 0 }
    return stats if hook.blank?

    pending_contacts.find_each { |contact| backfill_contact(contact, stats) }
    stats
  end

  private

  attr_reader :account

  def hook
    @hook ||= account.hooks.find_by(app_id: 'zoho_crm', status: 'enabled')
  end

  def leads_client
    @leads_client ||= Crm::Zoho::Api::LeadsClient.new(hook)
  end

  def contacts_client
    @contacts_client ||= Crm::Zoho::Api::ContactsClient.new(hook)
  end

  def backfill_contact(contact, stats)
    record, relinked_module = resolve_record(contact)
    sleep(RATE_LIMIT_DELAY)

    created_at = record && record['Created_Time']
    if created_at.blank?
      stats[:not_found] += 1
      return
    end

    ext = contact.additional_attributes['external']
    if relinked_module
      ext['zoho_id'] = record['id']
      ext['zoho_module'] = relinked_module
      stats[:relinked] += 1
    end
    ext['zoho_created_at'] = created_at
    contact.save!
    stats[:updated] += 1
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    stats[:errored] += 1
    Rails.logger.error("[ZOHO BACKFILL] account ##{account.id} contact ##{contact.id} error=#{e.message}")
  end

  # #find_any (Leads/search con converted: 'both') también resuelve leads que ya se convirtieron a
  # Deal — #find (GET Leads/{id}) los devuelve vacío en cuanto se convierten, ver
  # Crm::Zoho::Api::LeadsClient#find_any.
  def fetch_record(contact)
    ext = contact.additional_attributes['external']
    zoho_module = ext['zoho_module'].presence || 'Leads'

    zoho_module == 'Leads' ? leads_client.find_any(ext['zoho_id']) : contacts_client.find(ext['zoho_id'])
  end

  # [record, module] — si el zoho_id cacheado ya no resuelve (lead borrado/fusionado en Zoho), busca
  # por teléfono/email del contacto (misma búsqueda que Crm::Zoho::ContactFinderService al vincular
  # por primera vez), que casi siempre encuentra el registro vigente de esa persona — fusionado bajo
  # otro id, o vuelto a crear. `module` es nil cuando el zoho_id original sí resolvió (no hizo falta
  # relink) — así #backfill_contact sabe si tiene que sobrescribir zoho_id/zoho_module o no.
  def resolve_record(contact)
    record = fetch_record(contact)
    return [record, nil] if record.present?

    relinked_lead = leads_client.search(email: contact.email, phone: contact.phone_number).first
    return [relinked_lead, 'Leads'] if relinked_lead.present?

    relinked_contact = contacts_client.search(email: contact.email, phone: contact.phone_number).first
    return [relinked_contact, 'Contacts'] if relinked_contact.present?

    [nil, nil]
  end
end
