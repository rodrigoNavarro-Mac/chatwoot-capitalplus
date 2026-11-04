# Resuelve atribución determinística Lead->anuncio para leads con `social_lead_id` numérico
# poblado, usando el Hook DEDICADO `meta_lead_ads` (nunca el Hook `meta_ads` compartido con
# WhatsApp -- ver Fase 20/21/22 de la investigación de tesis IA). Solo lectura contra Meta, no
# modifica ningún registro de Meta ni de Zoho.
#
# No se ejecuta todavía en producción (fuera del alcance de la Fase 22, que es solo
# implementación local + pruebas) -- no está en config/schedule.yml ni se dispara desde ningún
# listener. Su activación requiere autorización explícita y específica, igual que el resto de
# esta investigación.
class RevenueIntelligence::ResolveMetaLeadAttributionsJob < ApplicationJob
  queue_as :scheduled_jobs

  # Límite de leads por corrida -- control de cuota básico (ver Koala::Facebook::APIError#fb_buc_usage
  # para telemetría real de uso de la API, a incorporar en una fase de endurecimiento posterior,
  # ver riesgos pendientes en Fase 22 §6). No pretende ser un rate limiter completo.
  DEFAULT_BATCH_SIZE = 200

  def perform(account_id = nil, batch_size: DEFAULT_BATCH_SIZE)
    hooks = Integrations::Hook.enabled.where(app_id: 'meta_lead_ads')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      resolve_for_hook(hook, batch_size)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::ResolveMetaLeadAttributionsJob] hook=#{hook.id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: hook.account).capture_exception
    end
  end

  private

  def resolve_for_hook(hook, batch_size)
    client = Koala::Facebook::API.new(hook.access_token)
    service = RevenueIntelligence::MetaLeadAttributionLookupService.new(client: client)

    # .limit + find_each no son compatibles en ActiveRecord (find_each ignora/pelea con limit) --
    # batch_size es un tope pequeño por diseño (control de cuota, ver DEFAULT_BATCH_SIZE), así
    # que basta con #each sobre el resultado ya acotado, sin batching adicional de find_each.
    eligible_leads(hook.account).limit(batch_size).each do |lead|
      resolve_lead(hook.account, lead, service)
    end
  end

  # Elegible: social_lead_id numérico (mismo criterio ya usado en las pruebas de Fase 18/20) y
  # sin atribución todavía resuelta (pendiente, o nunca intentada -- el left join cubre ambos
  # casos sin necesidad de crear la fila "pendiente" de antemano para cada lead elegible).
  #
  # Columnas calificadas con "revenue_leads." en todo el SQL crudo: revenue_lead_meta_attributions
  # TAMBIÉN tiene una columna social_lead_id (copia denormalizada), así que sin calificar el
  # nombre, el left_joins vuelve ambigua la referencia para Postgres (PG::AmbiguousColumn).
  def eligible_leads(account)
    account.revenue_leads
           .where(lead_source: 'Meta Ads')
           .where.not(revenue_leads: { social_lead_id: [nil, ''] })
           .where("revenue_leads.social_lead_id ~ '^[0-9]+$'")
           .left_joins(:meta_attribution)
           .where("revenue_lead_meta_attributions.id IS NULL OR revenue_lead_meta_attributions.verification_status = 'pendiente'")
  end

  def resolve_lead(account, lead, service)
    result = service.call(social_lead_id: lead.social_lead_id, created_at_source: lead.created_at_source)

    attribution = RevenueLeadMetaAttribution.find_or_initialize_by(revenue_lead_id: lead.id)
    attribution.account_id = account.id
    attribution.social_lead_id = lead.social_lead_id
    attribution.source = 'graph_api_leadgen_lookup'
    attribution.assign_attributes(result)
    attribution.save!
  end
end
