# Resuelve el correo del dueño (Owner) del Deal de Zoho al que pertenece una cotización, para el
# aviso automático que reemplaza al botón viejo de Zoho (crearCotizacionYEnviar) — ver
# Quotes::NotifyOwnerJob. Dos casos:
#
# - Cotización generada desde un Deal (source_type: 'deal'): el Owner ya viene en el payload que
#   se guardó en deal_snapshot al generar (Quotes::GenerateFromZohoDealService pide el campo
#   'Owner' explícitamente), no hace falta ninguna llamada nueva a Zoho.
# - Cotización generada desde un Producto (source_type: 'product', sin Deal): se busca el Deal ya
#   vinculado al contacto — el mismo cacheo que ya mantiene Crm::Zoho::DealsSyncJob en
#   additional_attributes.external.zoho_deal_id — y se le pide su Owner a Zoho. Si el contacto no
#   tiene un Deal vinculado (o el cacheo aún no corrió), no hay a quién avisar y se regresa nil.
class Quotes::ResolveOwnerEmailService
  def self.call(...)
    new(...).call
  end

  def initialize(quote:)
    @quote = quote
  end

  def call
    return email_from_snapshot if quote.deal?

    email_from_contacts_linked_deal
  end

  private

  attr_reader :quote

  def email_from_snapshot
    owner = quote.deal_snapshot['Owner']
    owner.is_a?(Hash) ? owner['email'].presence : nil
  end

  def email_from_contacts_linked_deal
    zoho_deal_id = linked_zoho_deal_id
    return nil if zoho_deal_id.blank?

    hook = quote.account.hooks.find_by(app_id: 'zoho_crm', status: 'enabled')
    return nil if hook.blank?

    deal = Crm::Zoho::Api::DealsClient.new(hook).find(zoho_deal_id, fields: ['Owner'])
    owner = deal.is_a?(Hash) ? deal['Owner'] : nil
    owner.is_a?(Hash) ? owner['email'].presence : nil
  end

  def linked_zoho_deal_id
    quote.contact&.additional_attributes&.dig('external', 'zoho_deal_id')
  end
end
