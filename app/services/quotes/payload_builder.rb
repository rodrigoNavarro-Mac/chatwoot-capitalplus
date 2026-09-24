# Arma un payload con la misma forma que un Deal de Zoho (mismas llaves que espera
# Quotes::CalculatorService) a partir de campos sueltos — usado cuando el origen NO es un Deal real
# (cotización por Producto, o edición manual desde el detalle), para poder reusar el calculador y
# Quotes::CalculateAndAttachService sin bifurcar la lógica de cálculo.
#
# Se usa la llave 'Desarollo' (una sola erre) a propósito, no por error: es lo que ya espera
# Quotes::CalculatorService, copiando el typo real del campo de Zoho Deals — como este payload es
# un contrato interno (no se manda a Zoho), lo importante es que coincida con lo que lee el
# calculador.
class Quotes::PayloadBuilder
  FIELD_MAP = {
    desarrollo: 'Desarollo',
    superficie: 'Superficie',
    precio_m2: 'Precio_por_m2',
    plazos: 'Plazos',
    enganche: 'Enganche',
    interes: 'Interes',
    meses_sin_intereses: 'Meses_sin_intereses',
    descuento: 'Descuento',
    fecha_entrega: 'Fecha_de_entrega',
    color: 'Color'
  }.freeze

  # `fields`: hash con llaves :nombre, :lote y las de FIELD_MAP (todas requeridas salvo :color).
  def self.build(fields)
    payload = { 'Deal_Name' => [fields[:nombre], fields[:lote]].compact_blank.join(' - ') }
    FIELD_MAP.each { |key, zoho_key| payload[zoho_key] = fields[key] }
    payload
  end
end
