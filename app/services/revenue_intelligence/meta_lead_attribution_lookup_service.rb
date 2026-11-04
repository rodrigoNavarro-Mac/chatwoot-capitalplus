# Consulta un leadgen_id de Meta y clasifica el resultado -- EXACTAMENTE la misma lógica ya
# probada manualmente contra producción en las Fases 18 y 20 de la investigación de tesis IA
# (docs/investigacion-tesis-ia/23_VALIDACION_SOCIAL_LEAD_ID_FASE18.md y
# 25_VERIFICACION_ADMINISTRATIVA_META_FASE20.md), ahora como código de producción reutilizable.
# No cambia el vocabulario de clasificación ni los criterios -- ver RevenueLeadMetaAttribution
# para la definición de cada estado.
#
# Pide únicamente los campos autorizados (nunca field_data ni nada de contacto). No registra
# tokens ni respuestas completas de Meta -- solo los campos ya modelados se propagan hacia el
# llamador.
class RevenueIntelligence::MetaLeadAttributionLookupService
  GRAPH_API_VERSION = 'v25.0'.freeze
  FIELDS = 'id,ad_id,adset_id,campaign_id,form_id,created_time'.freeze
  # Códigos de la Graph API consistentes con "permiso insuficiente / activo no accesible /
  # objeto no disponible" -- nunca se reclasifican como "no_correspondiente" (mismo criterio ya
  # aplicado manualmente en Fase 18/20: un bloqueo de permisos no es evidencia de un ID
  # incorrecto).
  PERMISSION_LIKE_CODES = [10, 200, 272].freeze
  # Tolerancia de consistencia de fecha entre Zoho y Meta -- mismo umbral ya usado en las
  # pruebas manuales (Fase 18/20: 2 días, cubre diferencias de huso horario/latencia de
  # sincronización sin ser tan ancho que deje de ser una verificación real).
  DATE_CONSISTENCY_TOLERANCE_DAYS = 2

  def initialize(client:)
    @client = client
  end

  # created_at_source: Time/DateTime de Zoho, usado solo para el chequeo de consistencia de
  # fecha -- nunca se persiste ni se reenvía a Meta.
  def call(social_lead_id:, created_at_source:)
    response = @client.get_object(social_lead_id, { fields: FIELDS }, { api_version: GRAPH_API_VERSION })
    result_from_response(response, social_lead_id, created_at_source)
  rescue Koala::Facebook::APIError => e
    result_from_error(e)
  end

  private

  def result_from_response(response, social_lead_id, created_at_source)
    id_match = response['id'].to_s == social_lead_id.to_s
    meta_created_at = parse_time(response['created_time'])
    fecha_consistente = date_consistent?(meta_created_at, created_at_source)
    complete = %w[ad_id adset_id campaign_id].all? { |f| response[f].present? }

    {
      verification_status: classify(id_match: id_match, complete: complete, fecha_consistente: fecha_consistente),
      meta_ad_id: response['ad_id'], meta_adset_id: response['adset_id'], meta_campaign_id: response['campaign_id'],
      meta_form_id: response['form_id'].presence, meta_lead_created_at: meta_created_at,
      fetch_error_code: nil, fetch_error_subcode: nil, fetched_at: Time.current
    }
  end

  def classify(id_match:, complete:, fecha_consistente:)
    return 'no_correspondiente' unless id_match
    return 'confirmada' if complete && fecha_consistente

    'parcialmente_verificable'
  end

  def result_from_error(error)
    permission_like = PERMISSION_LIKE_CODES.include?(error.fb_error_code.to_i) ||
                      error.fb_error_subcode.to_i == 33 ||
                      error.http_status.to_i == 400

    {
      verification_status: permission_like ? 'no_verificable_permisos_o_ausencia' : 'no_verificable_otro_error',
      meta_ad_id: nil, meta_adset_id: nil, meta_campaign_id: nil, meta_form_id: nil, meta_lead_created_at: nil,
      fetch_error_code: error.fb_error_code, fetch_error_subcode: error.fb_error_subcode,
      fetched_at: Time.current
    }
  end

  def date_consistent?(meta_created_at, created_at_source)
    return nil if meta_created_at.blank? || created_at_source.blank?

    (meta_created_at.to_date - created_at_source.to_date).to_i.abs <= DATE_CONSISTENCY_TOLERANCE_DAYS
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
