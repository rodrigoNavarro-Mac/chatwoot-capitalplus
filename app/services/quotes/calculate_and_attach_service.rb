# Segunda mitad compartida de la generación de una cotización: dado un Quote ya persistido y un
# payload con forma de Deal de Zoho (mismas llaves que espera Quotes::CalculatorService), calcula,
# persiste los campos, renderiza el HTML, genera el PDF y lo adjunta. Usado tanto por
# Quotes::GenerateFromZohoDealService (payload viene de un Deal real) como por
# Quotes::GenerateFromProductService y Api::V1::Accounts::QuotesController#update (payload armado a
# mano a partir de un Producto + edición manual) — así ninguno duplica esta cola de pasos.
class Quotes::CalculateAndAttachService
  CALCULATION_FIELDS = %i[
    nombre lote desarrollo plazos meses_sin_intereses superficie precio_m2 fecha_entrega
    monto_base descuento_aplicado monto enganche_pct enganche_monto interes_pct
    pago_mensual precio_total precio_m2_final schedule
  ].freeze

  def self.call(...)
    new(...).call
  end

  def initialize(quote:, payload:)
    @quote = quote
    @payload = payload
  end

  def call
    calculation = Quotes::CalculatorService.calculate(payload)
    persist_calculation(calculation)

    html = Quotes::HtmlRendererService.new(quote).render
    pdf_bytes = Quotes::PdfGeneratorService.new(html).generate
    attach_pdf(pdf_bytes)

    quote.update!(status: 'completed', render_payload: { html: html })
    quote
  rescue Quotes::CalculatorService::ValidationError => e
    quote.update!(status: 'failed', error_message: e.message)
    quote
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: quote.account).capture_exception
    quote.update!(status: 'failed', error_message: e.message)
    quote
  end

  private

  attr_reader :quote, :payload

  def persist_calculation(calc)
    quote.update!(calc.slice(*CALCULATION_FIELDS).merge(deal_snapshot: payload))
  end

  def attach_pdf(pdf_bytes)
    quote.pdf.purge if quote.pdf.attached?

    filename = "cotizacion-#{quote.lote.presence || quote.id}".parameterize
    quote.pdf.attach(
      io: StringIO.new(pdf_bytes),
      filename: "#{filename}.pdf",
      content_type: 'application/pdf'
    )
  end
end
