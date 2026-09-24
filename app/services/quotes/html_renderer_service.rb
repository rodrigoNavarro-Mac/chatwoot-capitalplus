# Arma el HTML final de app/views/quotes/pdf.html.erb con los valores ya calculados por
# Quotes::CalculatorService — ERB puro (sin ActionView::Base) porque es una sola plantilla
# estática, no una vista de un controller. Formatea moneda/fechas aquí para que la plantilla se
# quede "tonta" (solo interpolación, sin lógica).
class Quotes::HtmlRendererService
  include ActionView::Helpers::NumberHelper

  TEMPLATE_PATH = Rails.root.join('app/views/quotes/pdf.html.erb')

  def initialize(quote)
    @quote = quote
  end

  def render
    ERB.new(File.read(TEMPLATE_PATH), trim_mode: '-').result_with_hash(locals)
  end

  private

  attr_reader :quote

  def locals
    {
      lote: quote.lote.presence || quote.nombre,
      desarrollo: quote.desarrollo,
      superficie: number_with_precision(quote.superficie, precision: 2, delimiter: ','),
      precio_m2: currency(quote.precio_m2),
      importe: currency(quote.monto),
      enganche_pct: number_with_precision(quote.enganche_pct, precision: 2),
      plazos: quote.plazos,
      schedule: schedule_rows,
      total: currency(quote.precio_total)
    }
  end

  def schedule_rows
    Array(quote.schedule).map do |row|
      {
        periodo: row['periodo'] || row[:periodo],
        fecha: format_date(row['fecha'] || row[:fecha]),
        pago: currency(row['pago'] || row[:pago])
      }
    end
  end

  def format_date(value)
    Date.parse(value.to_s).strftime('%d/%m/%Y')
  rescue ArgumentError, TypeError
    value.to_s
  end

  def currency(amount)
    number_to_currency(amount, unit: '$', precision: 2, delimiter: ',', separator: '.', format: '%u%n')
  end
end
