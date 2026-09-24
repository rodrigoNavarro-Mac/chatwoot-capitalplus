# Punto de entrada para generar una Quote desde el botón del módulo Cotizaciones, cuando el origen
# es un Producto de Zoho CRM en vez de un Deal (ver Quotes::GenerateFromZohoDealService para el
# flujo por Deal, que sigue siendo el que usan el webhook de Zoho y el panel de la conversación).
#
# No vuelve a consultar Zoho aquí: el frontend ya trajo los datos del Producto al buscarlo y el
# usuario pudo haberlos editado antes de enviar el formulario — `fields` es exactamente lo que hay
# que calcular, `zoho_product_id` solo queda de referencia/auditoría.
class Quotes::GenerateFromProductService
  def self.call(...)
    new(...).call
  end

  def initialize(account:, zoho_product_id:, fields:, contact: nil, generated_by: nil)
    @account = account
    @zoho_product_id = zoho_product_id
    @fields = fields
    @contact = contact
    @generated_by = generated_by
  end

  def call
    quote = create_pending_quote
    payload = Quotes::PayloadBuilder.build(fields)
    Quotes::CalculateAndAttachService.call(quote: quote, payload: payload)
  end

  private

  attr_reader :account, :zoho_product_id, :fields, :contact, :generated_by

  def create_pending_quote
    account.quotes.create!(
      source_type: 'product',
      zoho_product_id: zoho_product_id,
      trigger_source: 'quotes_module',
      contact: contact,
      generated_by: generated_by,
      status: 'pending'
    )
  end
end
