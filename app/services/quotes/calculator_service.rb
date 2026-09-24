# Puerto a Ruby de la función Deluge `crearCotizacionYEnviar` (Zoho CRM → Zoho Creator) que
# calculaba el plan de pago de una cotización. Puro — sin I/O, sin ActiveRecord — recibe un payload
# con forma de Deal de Zoho (mismas llaves que devuelve la API) y devuelve los campos ya
# calculados. Ver payment_date para el ajuste de fin de semana y el desfase de un mes del primer
# pago — confirmados con el negocio 2026-09-24, difieren del script original.
class Quotes::CalculatorService
  class ValidationError < StandardError; end

  Inputs = Struct.new(:nombre, :lote, :plazos, :superficie, :precio_m2, :meses_sin_intereses, :descuento, keyword_init: true)

  def initialize(payload)
    @payload = payload || {}
  end

  def self.calculate(payload)
    new(payload).calculate
  end

  def calculate
    inputs = read_inputs
    validate!(inputs)
    enganche_pct, interes_pct = financing_rates(inputs.plazos)

    result = base_result(inputs, enganche_pct, interes_pct)
    plan = inputs.plazos.zero? ? cash_plan(result[:monto]) : financed_plan(result[:monto], enganche_pct, interes_pct, inputs)
    result.merge!(plan)
    result[:precio_m2_final] = (result[:precio_total] / inputs.superficie).round(2)
    result
  end

  private

  attr_reader :payload

  def read_inputs
    nombre, lote = parse_deal_name
    Inputs.new(
      nombre: nombre,
      lote: lote,
      plazos: required_integer('Plazos', 'Plazo'),
      superficie: required_decimal('Superficie', 'Superficie'),
      precio_m2: required_decimal('Precio_por_m2', 'Precio por m2'),
      meses_sin_intereses: optional_integer('Meses_sin_intereses'),
      descuento: optional_decimal('Descuento')
    )
  end

  def validate!(inputs)
    raise ValidationError, 'El plazo no puede ser menor a 0.' if inputs.plazos.negative?
    raise ValidationError, 'La superficie debe ser mayor a 0.' if inputs.superficie <= 0
    raise ValidationError, 'El precio por m2 no puede ser negativo.' if inputs.precio_m2.negative?
  end

  def base_result(inputs, enganche_pct, interes_pct)
    meses_sin_intereses = inputs.plazos.zero? ? 0 : inputs.meses_sin_intereses
    monto_base = inputs.superficie * inputs.precio_m2
    descuento_aplicado = discount_amount(inputs.descuento, monto_base)
    monto = [monto_base - descuento_aplicado, BigDecimal(0)].max

    {
      nombre: inputs.nombre,
      lote: inputs.lote,
      desarrollo: payload['Desarollo'],
      plazos: inputs.plazos,
      meses_sin_intereses: meses_sin_intereses,
      superficie: inputs.superficie,
      precio_m2: inputs.precio_m2,
      fecha_entrega: fecha_entrega,
      monto_base: monto_base.round(2),
      descuento_aplicado: descuento_aplicado.round(2),
      monto: monto.round(2),
      enganche_pct: enganche_pct.round(3),
      interes_pct: interes_pct.round(3)
    }
  end

  def parse_deal_name
    deal_name = payload['Deal_Name'].to_s
    idx = deal_name.index('-')
    return [deal_name.strip, ''] unless idx

    [deal_name[0...idx].strip, deal_name[(idx + 1)..].to_s.strip]
  end

  def fecha_entrega
    raw = payload['Fecha_de_entrega']
    return Date.current if raw.blank?

    Date.parse(raw.to_s)
  rescue ArgumentError
    Date.current
  end

  def financing_rates(plazos)
    return [BigDecimal(0), BigDecimal(0)] if plazos.zero?

    enganche = required_percentage('Enganche', 'Enganche')
    interes = required_percentage('Interes', 'Interés')
    [normalize_rate(enganche), normalize_rate(interes)]
  end

  # Zoho a veces manda el % como fracción (0.2) y a veces como número entero (20) — se normaliza a
  # porcentaje entero igual que el script original.
  def normalize_rate(value)
    value <= 1 ? value * 100 : value
  end

  def discount_amount(descuento, monto_base)
    return BigDecimal(0) if descuento.zero?

    descuento > 100 ? descuento : (monto_base * descuento) / 100
  end

  def cash_plan(monto)
    {
      enganche_monto: BigDecimal(0),
      pago_mensual: BigDecimal(0),
      precio_total: monto.round(2),
      schedule: [{
        periodo: 1,
        fecha: fecha_entrega.iso8601,
        saldo_inicial: monto.round(2),
        interes: BigDecimal(0),
        capital: monto.round(2),
        pago: monto.round(2),
        saldo_final: BigDecimal(0)
      }]
    }
  end

  def financed_plan(monto, enganche_pct, interes_pct, inputs)
    enganche_monto = (monto * enganche_pct / 100).round(2)
    principal = monto - enganche_monto
    monthly_rate = (interes_pct / 100) / 12
    meses_con_interes = inputs.plazos - inputs.meses_sin_intereses

    factor = amortization_factor(monthly_rate, inputs.meses_sin_intereses, meses_con_interes)
    pago_mensual = (principal / (factor.positive? ? factor : BigDecimal(inputs.plazos.to_s))).round(2)
    schedule = build_schedule(principal, pago_mensual, monthly_rate, inputs.plazos, inputs.meses_sin_intereses)

    {
      enganche_monto: enganche_monto,
      pago_mensual: pago_mensual,
      precio_total: (enganche_monto + schedule.sum { |row| row[:pago] }).round(2),
      schedule: schedule
    }
  end

  def amortization_factor(monthly_rate, meses_sin_intereses, meses_con_interes)
    factor_con_interes = BigDecimal(0)
    factor_con_interes = (1 - (1 / ((1 + monthly_rate)**meses_con_interes))) / monthly_rate if monthly_rate.positive? && meses_con_interes.positive?

    meses_sin_intereses + factor_con_interes
  end

  def build_schedule(principal, pago_mensual, monthly_rate, plazos, meses_sin_intereses)
    saldo = principal
    (1..plazos).map do |periodo|
      interes, capital = period_interest_and_capital(saldo, pago_mensual, monthly_rate, periodo, meses_sin_intereses)
      capital = saldo.round(2) if periodo == plazos
      pago = (capital + interes).round(2)
      saldo_final = (saldo - capital).round(2)

      row = { periodo: periodo, fecha: payment_date(periodo).iso8601, saldo_inicial: saldo.round(2),
              interes: interes, capital: capital, pago: pago, saldo_final: saldo_final }
      saldo = saldo_final
      row
    end
  end

  def period_interest_and_capital(saldo, pago_mensual, monthly_rate, periodo, meses_sin_intereses)
    return [BigDecimal(0), pago_mensual] if (periodo - 1) < meses_sin_intereses

    interes = (saldo * monthly_rate).round(2)
    [interes, (pago_mensual - interes).round(2)]
  end

  # `fecha_entrega` es la fecha de firma/pago de enganche — el primer pago mensual cae un mes
  # después de esa fecha (por eso `payment_date` se llama con `periodo`, no `periodo - 1`).
  #
  # Los pagos nunca caen en fin de semana: se mueven al día hábil más cercano (sábado -> viernes,
  # domingo -> lunes). Esto reemplaza el ajuste que traía el script original de Deluge — ese
  # ajuste resultó ser el mismo cálculo mal portado a Ruby (Deluge's getDayOfWeek() numera
  # domingo=1..sábado=7, no lunes=1..domingo=7 como asumí al portarlo, así que el resultado
  # anterior quedaba invertido) — confirmado con el negocio 2026-09-24.
  def payment_date(months_ahead)
    date = fecha_entrega >> months_ahead
    case date.wday
    when 0 then date + 1 # domingo -> lunes
    when 6 then date - 1 # sábado -> viernes
    else date
    end
  end

  def required_integer(key, label)
    raw = payload[key]
    raise ValidationError, "Valor faltante: #{label}." if raw.blank?

    raw.to_s.to_i
  end

  def optional_integer(key)
    raw = payload[key].presence
    raw ? raw.to_s.to_i : 0
  end

  def required_decimal(key, label)
    raw = payload[key]
    raise ValidationError, "Valor faltante: #{label}." if raw.blank?

    BigDecimal(raw.to_s)
  end

  def required_percentage(key, label)
    raw = payload[key]
    raise ValidationError, "Valor faltante: #{label}." if raw.blank?

    BigDecimal(raw.to_s.delete('%'))
  end

  def optional_decimal(key)
    raw = payload[key]
    return BigDecimal(0) if raw.blank?

    BigDecimal(raw.to_s.delete('%'))
  end
end
