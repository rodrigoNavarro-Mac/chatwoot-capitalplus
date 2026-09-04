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

  def qualification_attrs
    {
      created_at_source: parse_time(payload['Created_Time']),
      first_contact_at: parse_time(payload['First_Contact_Time']),
      qualified_at: parse_time(payload['Fecha_de_calificaci_n']),
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

  def marketing_attrs
    {
      lead_source: payload['Lead_Source'],
      campaign_id: payload.dig('Campa_a', 'id'),
      campaign_name: payload['Campaing_Name'].presence || payload.dig('Campa_a', 'name')
    }
  end

  def meta_ads_attrs
    {
      ad_account_id: payload['Ad_Account_Id'],
      ad_account_name: payload['Ad_Account_Name'],
      adset_id: payload['Adset_Id'],
      adset_name: payload['Adset_Name'],
      advert_id: payload['Advert_Id'],
      advert_name: payload['Advert_name'],
      form_id: payload['Form_Id'],
      form_name: payload['Form_Name'],
      platform: payload['Plataforma']
    }
  end

  def traceability_attrs
    {
      attempt_count: payload['Contador_Intentos'].to_i,
      reassignment_count: payload['Numero_Reasignaciones'].to_i
    }
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
