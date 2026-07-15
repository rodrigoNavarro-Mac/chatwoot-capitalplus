# Resuelve el valor de "razón de compra" de un lead para decidir qué CadenceDefinition
# (segmento) le corresponde. Zoho es la fuente de verdad: si el contacto ya está vinculado
# a un registro de Zoho (Lead/Contact), se consulta ese campo en vivo. Solo si el contacto
# todavía no existe en Zoho (lead nuevo, recién capturado) se usa el valor que el bot de
# WhatsApp guardó localmente en conversation.custom_attributes — un respaldo temporal
# hasta que exista el registro real en Zoho.
class Cadences::RazonCompraResolver
  ZOHO_FIELD = 'Raz_n_de_compra'.freeze
  LOCAL_ATTRIBUTE = 'razon_compra'.freeze

  pattr_initialize [:conversation!]

  def resolve
    from_zoho.presence || from_conversation.presence
  end

  private

  delegate :contact, :account, to: :conversation

  def from_zoho
    return nil if contact.blank? || zoho_hook.blank?

    record = Crm::Zoho::ContactFinderService.new(zoho_hook).fetch_record(contact)
    record&.dig(ZOHO_FIELD)
  rescue StandardError => e
    Rails.logger.error("[Cadences::RazonCompraResolver] Zoho lookup failed contact=#{contact&.id}: #{e.message}")
    nil
  end

  def from_conversation
    conversation.custom_attributes[LOCAL_ATTRIBUTE]
  end

  def zoho_hook
    @zoho_hook ||= Integrations::Hook.find_by(account: account, app_id: 'zoho_crm', status: 'enabled')
  end
end
