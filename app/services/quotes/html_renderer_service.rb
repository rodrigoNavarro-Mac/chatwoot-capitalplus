# Arma el HTML final de app/views/quotes/pdf.html.erb con los valores ya calculados por
# Quotes::CalculatorService — ERB puro (sin ActionView::Base) porque es una sola plantilla
# estática, no una vista de un controller. Formatea moneda/fechas aquí para que la plantilla se
# quede "tonta" (solo interpolación, sin lógica).
class Quotes::HtmlRendererService
  include ActionView::Helpers::NumberHelper
  include ERB::Util

  TEMPLATE_PATH = Rails.root.join('app/views/quotes/pdf.html.erb')
  AMORTIZATION_TEMPLATE_PATH = Rails.root.join('app/views/quotes/amortization_pdf.html.erb')

  # El diseño original (tier 0) está pensado para ~12 meses. Con financiamientos más largos
  # (hasta 48 meses, el máximo que soporta Quotes::CalculatorService) la tabla no cabe en una
  # sola página de PDF a menos que se encoja el header y el resto del espaciado — se prioriza
  # encoger el header primero (es el costo fijo más grande) y solo se toca el tamaño de fuente de
  # la tabla en los tramos más largos. Los números están verificados renderizando con Gotenberg y
  # contando páginas reales para 24/36/48 meses, no son solo una estimación.
  COMPACT_TIERS = [
    { max_rows: 14, vars: {} },
    { max_rows: 24, vars: {
      'header-h' => '140px', 'header-pad' => '20px 60px 20px 66px', 'header-copy-size' => '15px',
      'logo-wrap-w' => '185px', 'logo-wrap-h' => '95px', 'logo-w' => '176px', 'logo-h' => '88px',
      'content-pad' => '26px 66px 20px 66px', 'top-data-mb' => '18px',
      'table-title-pad' => '10px 22px 6px', 'th-pad' => '5px 22px', 'td-pad' => '3px 22px',
      'table-font' => '11px', 'total-mt' => '10px', 'total-pad' => '3px 22px 3px', 'total-font' => '18px'
    } },
    { max_rows: 36, vars: {
      'header-h' => '95px', 'header-pad' => '14px 50px 14px 60px', 'header-copy-size' => '13px',
      'logo-wrap-w' => '112px', 'logo-wrap-h' => '60px', 'logo-w' => '108px', 'logo-h' => '54px',
      'content-pad' => '16px 66px 14px 66px', 'top-data-mb' => '12px',
      'table-title-pad' => '6px 22px 4px', 'th-pad' => '3px 22px', 'td-pad' => '1.5px 22px',
      'table-font' => '10px', 'total-mt' => '6px', 'total-pad' => '2px 22px 2px', 'total-font' => '15px'
    } },
    { max_rows: Float::INFINITY, vars: {
      'header-h' => '70px', 'header-pad' => '8px 40px 8px 50px', 'header-copy-size' => '11px',
      'logo-wrap-w' => '88px', 'logo-wrap-h' => '48px', 'logo-w' => '84px', 'logo-h' => '42px',
      'content-pad' => '10px 66px 10px 66px', 'top-data-mb' => '8px',
      'table-title-pad' => '4px 22px 3px', 'th-pad' => '2px 22px', 'td-pad' => '0.5px 22px',
      'table-font' => '9px', 'total-mt' => '4px', 'total-pad' => '1px 22px 1px', 'total-font' => '13px'
    } }
  ].freeze

  def initialize(quote)
    @quote = quote
  end

  def render
    ERB.new(File.read(TEMPLATE_PATH), trim_mode: '-').result_with_hash(locals)
  end

  # Versión "interna" con el desglose completo (interés/capital/saldo por periodo) — a diferencia
  # de #render, esta no intenta caber en una sola página: son documentos de consulta/contabilidad,
  # no el PDF que se le entrega al cliente, así que se deja fluir a varias páginas con el thead
  # repitiéndose (ver `thead{display:table-header-group}` en la plantilla).
  def render_amortization
    ERB.new(File.read(AMORTIZATION_TEMPLATE_PATH), trim_mode: '-').result_with_hash(amortization_locals)
  end

  private

  attr_reader :quote

  # `lote`/`desarrollo` vienen del payload de Zoho (Deal_Name/Desarollo, texto libre capturado por
  # ventas) — se escapan explícitamente porque este HTML no solo se manda a Gotenberg, también se
  # muestra embebido (iframe) en el módulo de Cotizaciones del dashboard.
  def locals
    quote_summary_locals.merge(schedule: schedule_rows, compact_style: compact_style)
  end

  def amortization_locals
    quote_summary_locals.merge(
      nombre: h(quote.nombre),
      interes_pct: number_with_precision(quote.interes_pct, precision: 2),
      pago_mensual: currency(quote.pago_mensual),
      schedule: amortization_schedule_rows
    )
  end

  def quote_summary_locals
    text_locals.merge(
      superficie: number_with_precision(quote.superficie, precision: 2, delimiter: ','),
      precio_m2: currency(quote.precio_m2),
      importe: currency(quote.monto),
      enganche_pct: number_with_precision(quote.enganche_pct, precision: 2),
      plazos: quote.plazos,
      total: currency(quote.precio_total)
    )
  end

  def text_locals
    { lote: h(quote.lote.presence || quote.nombre), desarrollo: h(quote.desarrollo) }
  end

  def schedule_rows
    @schedule_rows ||= Array(quote.schedule).map do |row|
      { periodo: row_value(row, :periodo), fecha: format_date(row_value(row, :fecha)), pago: currency(row_value(row, :pago)) }
    end
  end

  def amortization_schedule_rows
    Array(quote.schedule).map do |row|
      {
        periodo: row_value(row, :periodo),
        fecha: format_date(row_value(row, :fecha)),
        saldo_inicial: currency(row_value(row, :saldo_inicial)),
        interes: currency(row_value(row, :interes)),
        capital: currency(row_value(row, :capital)),
        pago: currency(row_value(row, :pago)),
        saldo_final: currency(row_value(row, :saldo_final))
      }
    end
  end

  # `quote.schedule` es jsonb: llega con llaves string desde la base, pero symbol cuando se arma
  # en memoria justo después de calcular (antes del primer save) — se soportan ambas.
  def row_value(row, key)
    row[key.to_s] || row[key]
  end

  def compact_style
    vars = COMPACT_TIERS.find { |tier| schedule_rows.size <= tier[:max_rows] }[:vars]
    return '' if vars.empty?

    ":root{#{vars.map { |name, value| "--#{name}:#{value}" }.join(';')}}"
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
