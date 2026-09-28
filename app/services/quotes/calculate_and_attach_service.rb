# Segunda mitad compartida de la generación de una cotización: dado un Quote ya persistido y un
# payload con forma de Deal de Zoho (mismas llaves que espera Quotes::CalculatorService), calcula,
# persiste los campos, renderiza el HTML, genera el PDF y lo adjunta. Usado tanto por
# Quotes::GenerateFromZohoDealService (payload viene de un Deal real) como por
# Quotes::GenerateFromProductService y Api::V1::Accounts::QuotesController#update (payload armado a
# mano a partir de un Producto + edición manual) — así ninguno duplica esta cola de pasos.
#
# También aplica aquí la regla de negocio por desarrollo (QuoteDevelopmentRule), porque corre
# tanto en la generación inicial como en cada edición/recálculo: según el tramo (QuoteDevelopmentRuleTier)
# donde cae el plazo, la cotización se recalcula a meses sin intereses por todo el plazo
# automáticamente (sin importar qué haya mandado el usuario) y/o queda `authorization_status:
# pending` (su PDF no se puede descargar hasta que se apruebe).
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
    generate!
    quote
  rescue Quotes::CalculatorService::ValidationError => e
    fail!(e.message)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: quote.account).capture_exception
    fail!(e.message)
  end

  private

  attr_reader :quote, :payload

  def generate!
    effective_payload = apply_development_rule(payload)
    calculation = Quotes::CalculatorService.calculate(effective_payload)
    persist_calculation(effective_payload, calculation)

    html = Quotes::HtmlRendererService.new(quote).render
    pdf_bytes = Quotes::PdfGeneratorService.new(html).generate
    attach_pdf(pdf_bytes)

    quote.update!(completion_attrs(html, effective_payload))
  end

  def fail!(message)
    quote.update!(status: 'failed', error_message: message)
    quote
  end

  # Fuerza meses_sin_intereses = plazos (todo el plazo) cuando el tramo que cubre este plazo tiene
  # msi: true — no aplica a contado (Plazos == 0), que no tiene financiamiento.
  def apply_development_rule(original_payload)
    plazos = original_payload['Plazos'].to_i
    tier = matching_tier(plazos)
    return original_payload unless plazos.positive? && tier&.msi?

    original_payload.merge('Meses_sin_intereses' => plazos)
  end

  def completion_attrs(html, effective_payload)
    { status: 'completed', render_payload: { html: html }, authorization_status: authorization_status_for(effective_payload) }
  end

  def authorization_status_for(effective_payload)
    plazos = effective_payload['Plazos'].to_i
    tier = matching_tier(plazos)
    return 'not_required' unless tier

    tier.requires_authorization? ? 'pending' : 'not_required'
  end

  def matching_tier(plazos)
    rule = development_rule
    return nil unless rule && plazos.positive?

    rule.tier_for(plazos)
  end

  def development_rule
    return @development_rule if defined?(@development_rule)

    @development_rule = quote.account.quote_development_rules
                             .includes(:quote_development_rule_tiers)
                             .find_by(desarrollo: payload['Desarollo'])
  end

  def persist_calculation(source_payload, calc)
    quote.update!(calc.slice(*CALCULATION_FIELDS).merge(deal_snapshot: source_payload))
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
