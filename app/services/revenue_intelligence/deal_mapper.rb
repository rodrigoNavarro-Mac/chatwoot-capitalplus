# Traduce un payload crudo de Zoho Deals (tal como lo devuelve Crm::Zoho::Api::DealsClient) a los
# atributos de RevenueDeal. Puro — no toca la base de datos ni hace llamadas de red.
class RevenueIntelligence::DealMapper
  # Campos de cotización: existen en Zoho pero el MVP no construye lógica analítica sobre ellos —
  # se preservan verbatim en quote_fields (jsonb) si vienen en el payload, nada más.
  QUOTE_FIELDS = %w[Precio_por_m2 Superficie Descuento Enganche Plazos Meses_sin_intereses
                    Precio_a_Meses Fecha_de_entrega Tiene_el_presupuesto Productos_de_interes].freeze

  def self.map(payload)
    new(payload).map
  end

  def initialize(payload)
    @payload = payload || {}
  end

  def map
    stage = payload['Stage']

    identity_attrs.merge(pipeline_attrs(stage)).merge(
      won: stage == RevenueDeal::WON_STAGE,
      lost: stage == RevenueDeal::LOST_STAGE,
      reason_for_loss: payload['Reason_For_Loss__s'],
      quote_fields: quote_fields,
      raw_payload: payload
    )
  end

  private

  attr_reader :payload

  def identity_attrs
    {
      owner_id: payload.dig('Owner', 'id'),
      owner_name: payload.dig('Owner', 'name'),
      # OJO: el campo fuente es "Desarollo" (una sola erre) — typo real y confirmado de esta
      # cuenta Zoho, distinto de "Desarrollo" en Leads. No "corregir" sin verificar contra Zoho.
      desarrollo: payload['Desarollo']
    }
  end

  def pipeline_attrs(stage)
    {
      stage: stage,
      pipeline: payload['Pipeline'],
      probability: payload['Probability'],
      amount: payload['Amount'],
      expected_revenue: payload['Expected_Revenue'],
      lead_source: payload['Lead_Source'],
      campaign_source: campaign_source_value,
      created_at_source: parse_time(payload['Created_Time']),
      stage_modified_at: parse_time(payload['Stage_Modified_Time']),
      closing_date: parse_date(payload['Closing_Date'])
    }
  end

  # Campaign_Source es un lookup ({id, name}) en la mayoría de los payloads reales, pero se
  # defiende contra el caso de que llegue como string plano (u otro shape inesperado de la API).
  def campaign_source_value
    value = payload['Campaign_Source']
    value.is_a?(Hash) ? value['name'] : value
  end

  def quote_fields
    QUOTE_FIELDS.index_with { |field| payload[field] }.compact
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
