# Trae en lote (vía COQL) el Deal más reciente vinculado a cada Zoho Contact, para no hacer
# un request por contacto al sincronizar el estado de deals (ver Crm::Zoho::DealsSyncJob).
class Crm::Zoho::Api::DealsClient < Crm::Zoho::Api::BaseClient
  # Límite de filas por consulta COQL de Zoho (v7). Con este tamaño de lote alcanza holgura
  # para contactos con más de un Deal sin necesitar paginar dentro de un mismo batch.
  CONTACT_BATCH_SIZE = 100

  # contact_ids: ids de Zoho Contacts (no Leads: los Deals siempre se crean contra Contact_Name,
  # ver Api::V1::Accounts::Integrations::ZohoCrmController#create_deal).
  # Devuelve { zoho_contact_id => { deal_id:, stage:, modified_time: } } quedándose, por contacto,
  # con el Deal modificado más recientemente si hay varios.
  def deals_by_contact_ids(contact_ids)
    batches = contact_ids.map(&:to_s).uniq.each_slice(CONTACT_BATCH_SIZE)
    batches.with_object({}) do |batch, result|
      fetch_batch(batch).each { |row| accumulate_latest(result, row) }
    end
  end

  private

  def accumulate_latest(result, row)
    contact_id = row.dig('Contact_Name', 'id')
    return unless contact_id

    current = result[contact_id]
    return if current && current[:modified_time].to_s >= row['Modified_Time'].to_s

    result[contact_id] = { deal_id: row['id'], stage: row['Stage'], modified_time: row['Modified_Time'] }
  end

  def fetch_batch(contact_ids)
    ids = contact_ids.map { |id| "'#{id.delete("'")}'" }.join(',')
    query = "select id, Stage, Contact_Name, Modified_Time from Deals where Contact_Name.id in (#{ids}) limit 200"

    response = post('coql', { select_query: query })
    Array(response['data'])
  rescue Crm::Zoho::Api::BaseClient::ApiError => e
    return [] if e.code == 204

    raise
  end
end
