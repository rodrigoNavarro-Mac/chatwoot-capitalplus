# Traduce un payload crudo de Zoho Leads (tal como lo devuelve Crm::Zoho::Api::LeadsClient) a los
# atributos de RevenueLead. Puro — no toca la base de datos ni hace llamadas de red, solo mapea
# un hash a otro. `raw_payload` completo siempre se conserva en el resultado, para auditoría/
# re-mapeo sin volver a golpear la API de Zoho.
class RevenueIntelligence::LeadMapper
  def self.map(payload)
    new(payload).map
  end

  def initialize(payload)
    @payload = payload || {}
  end

  def map
    [identity_attrs, qualification_attrs, profile_attrs, budget_attrs, marketing_attrs, meta_ads_attrs, traceability_attrs]
      .reduce(:merge).merge(raw_payload: payload)
  end

  private

  attr_reader :payload

  def identity_attrs
    {
      owner_id: payload.dig('Owner', 'id'),
      owner_name: payload.dig('Owner', 'name'),
      desarrollo: payload['Desarrollo']
    }
  end

  # 'Contactado' es el valor exacto de Lead_Status que el reporte semanal operativo ya usa como
  # "lead de calidad"/contactado de verdad (ver V2::Reports::ZohoLeadsMetrics::CONTACTED_STATUS,
  # confirmado contra la API real 2026-08-18) -- lo mantiene el equipo de ventas a mano en Zoho, a
  # diferencia de First_Contact_Time (que solo marca que el AGENTE mandó un mensaje, sin importar
  # si el cliente respondió o el lead de verdad se trabajó). 'Calificado' también cuenta -- es una
  # etapa posterior a Contactado (no se califica a alguien sin haberle hablado), y Lead_Status ya
  # no dice 'Contactado' una vez que el lead avanzó ahí (mismo error de "etapa actual vs. etapa
  # máxima alcanzada" ya documentado para el embudo viejo, ver
  # project_revenue_intelligence_requisitos_pendientes).
  CONTACTED_LEAD_STATUSES = ['Contactado', 'Calificado'].freeze

  # 'Cliente perdido/Descartado' (44% de los leads de esta cuenta) es ambiguo por sí solo -- un
  # lead se descarta tanto por "no le interesó DESPUÉS de hablar con él" (sí se contactó) como por
  # "nunca se pudo localizar" (nunca se contactó). Raz_n_de_descarte desambigua: confirmado contra
  # el desglose real de la cuenta (2026-09-15) que ~72% de los descartados tiene una razón que solo
  # se conoce hablando con la persona (no le interesó, no tenía presupuesto, no le gustó el
  # producto, etc.) -- esas SÍ cuentan como contactadas. Estas dos razones confirman que nunca se
  # logró contactar; una razón vacía (~8% de los descartados, sin dato para decidir) se trata igual
  # como NO contactado, por default conservador -- confirmado con el usuario.
  DISCARDED_LEAD_STATUSES = ['Cliente perdido/Descartado', 'Lost Lead'].freeze
  NEVER_REACHED_DISCARD_REASONS = [
    'ILOCALIZABLE (NÚMERO Y CORREO INCORRECTOS)',
    'NO CONTESTÓ (DESPUES DE 5 INTENTOS)'
  ].freeze

  def qualification_attrs
    {
      created_at_source: parse_time(payload['Created_Time']),
      first_contact_at: contacted_at,
      qualified_at: parse_time(payload['Fecha_de_calificaci_n']),
      qualification_channel: payload['Canal_de_calificaci_n'],
      lead_status: payload['Lead_Status'],
      discard_reason: payload['Raz_n_de_descarte'],
      razon_compra: payload['Raz_n_de_compra'],
      plazo: payload['Tiempo_de_inversi_n']
    }
  end

  def profile_attrs
    {
      genero: payload['G_nero'],
      ocupacion: payload['Ocupaci_n'],
      estado_civil: payload['Estado_civil'],
      etapa_vida: payload['Etapa_de_vida'],
      nacionalidad: payload['Nacionalidad'],
      rango_edad: payload['Rango_de_edad']
    }
  end

  # presupuesto_raw se conserva SIEMPRE, sin importar si BudgetParser logra extraer algo.
  def budget_attrs
    parsed = RevenueIntelligence::BudgetParser.parse(payload['Presupuesto'])
    { presupuesto_raw: payload['Presupuesto'], presupuesto_min: parsed[:min], presupuesto_max: parsed[:max] }
  end

  # campaign_id/adset_id/advert_id son la clave de identidad usada para agrupar en el rollup de
  # Marketing (ver RefreshAggregatesJob#campaign_rows) — para esta cuenta, Zoho NUNCA llena el
  # lookup "Campa_a" ni Adset_Id/Advert_Id (confirmado contra payloads reales: siempre nil),
  # solo los campos de nombre libre. Sin fallback, campaign_id sale nil en el 100% de los leads y
  # la pestaña Marketing queda vacía. Se usa el nombre como id cuando no hay lookup real.
  def marketing_attrs
    {
      lead_source: payload['Lead_Source'],
      campaign_id: payload.dig('Campa_a', 'id') || payload['Campaing_Name'],
      campaign_name: payload['Campaing_Name'].presence || payload.dig('Campa_a', 'name')
    }
  end

  def meta_ads_attrs
    {
      ad_account_id: payload['Ad_Account_Id'],
      ad_account_name: payload['Ad_Account_Name'],
      adset_id: payload['Adset_Id'] || payload['Adset_Name'],
      adset_name: payload['Adset_Name'],
      advert_id: payload['Advert_Id'] || payload['Advert_name'],
      advert_name: payload['Advert_name'],
      form_id: payload['Form_Id'],
      form_name: payload['Form_Name'],
      platform: payload['Plataforma']
    }.merge(lead_source_extra_attrs)
  end

  # Confirmados contra la cuenta real vía Zoho CRM API getFields, faltaban de Fase 1.
  def lead_source_extra_attrs
    {
      page_id: payload['Page_Id'],
      page_name: payload['Page_Name'],
      social_lead_id: payload['leadchain0__Social_Lead_ID'],
      lead_type: payload['Lead_Type']
    }
  end

  def traceability_attrs
    {
      attempt_count: payload['Contador_Intentos'].to_i,
      reassignment_count: payload['Numero_Reasignaciones'].to_i
    }
  end

  def contacted_at
    return nil unless considered_contacted?

    parse_time(payload['First_Contact_Time']) || parse_time(payload['Modified_Time'])
  end

  def considered_contacted?
    status = payload['Lead_Status']
    return true if CONTACTED_LEAD_STATUSES.include?(status)
    return false unless DISCARDED_LEAD_STATUSES.include?(status)

    discard_reason = payload['Raz_n_de_descarte']
    discard_reason.present? && NEVER_REACHED_DISCARD_REASONS.exclude?(discard_reason)
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
