# Deals de Zoho CREADOS en el periodo de un desarrollo que no vienen de la cohorte de "leads nuevos
# del periodo" del embudo de ventas (V2::Reports::SalesFunnelBuilder) — separado de esa clase solo
# para no pasar su límite de tamaño de módulo, mismo criterio ya usado con
# V2::Reports::ZohoLeadsMetrics/WeeklyOpsReportCallsMetrics.
#
# Un lead que llegó antes del periodo y cuyo deal se creó justo esta semana quedaba invisible para
# el embudo (que solo mira la cohorte de leads nuevos) aunque el deal existiera y se viera en el
# kanban de Zoho — caso real detectado 2026-08-24. Se separan dos poblaciones fuera de la cohorte:
#
# - "activity" (actividad): deals con un contacto de Chatwoot vinculado, pero ese contacto no es
#   parte de la cohorte del periodo.
# - "external" (externo): deals sin NINGÚN contacto de Chatwoot en absoluto — caso real detectado
#   2026-08-25, un lead creado en Zoho meses antes (vía Meta Ads, nunca escribió por WhatsApp) que
#   recién generó un deal. Crm::Zoho::DealsSyncJob solo actualiza contactos que YA existen en
#   Chatwoot, así que ese deal no tiene con qué vincularse — sin este bucket desaparecía del embudo
#   por completo en vez de contar como algo.
#
# Ninguno de los dos captura un deal viejo que solo AVANZÓ de etapa esta semana sin haberse creado
# en ella — eso requeriría el historial de cambios de etapa de Zoho, que esta integración no
# consulta.
class V2::Reports::SalesFunnelDealActivity
  def initialize(account:, range:)
    @account = account
    @range = range
  end

  # with_deal_contact_ids: ids de contacto de la cohorte de "leads nuevos con deal" del embudo —
  # cualquier deal cuyo contacto ya esté ahí se descarta para no contarlo dos veces. visita_efectiva/
  # closed_won no necesitan su propio chequeo de "ya contado" contra la cohorte: como esas etapas ya
  # son subconjuntos de "con deal" en el embudo, cualquier contacto fuera de with_deal_contact_ids
  # está automáticamente fuera de ambas también.
  def outside_cohort(development_key, with_deal_contact_ids)
    zero = { has_deal: 0, visita_efectiva: 0, closed_won: 0, external: 0, external_visita_efectiva: 0, external_closed_won: 0 }
    return zero if development_key.blank?

    linked_stages, external_stages = deal_stages_by_linkage(development_key)
    extra = linked_stages.except(*with_deal_contact_ids)

    {
      has_deal: extra.size,
      visita_efectiva: extra.count { |_id, stage| visita_efectiva_stages.include?(stage) },
      closed_won: extra.count { |_id, stage| closed_won_stages.include?(stage) },
      external: external_stages.size,
      external_visita_efectiva: external_stages.count { |stage| visita_efectiva_stages.include?(stage) },
      external_closed_won: external_stages.count { |stage| closed_won_stages.include?(stage) }
    }
  end

  private

  attr_reader :account, :range

  # Deals creados en el periodo, separados en `linked` ({ chatwoot_contact_id => etapa actual }, para
  # los que sí tienen un contacto vinculado vía zoho_deal_id cacheado por Crm::Zoho::DealsSyncJob) y
  # `external` (array de etapas de los que no tienen ningún contacto en Chatwoot).
  def deal_stages_by_linkage(development_key)
    deals = Crm::Zoho::DealsForPeriodService.new(account: account, development_key: development_key, range: range).fetch
    return [{}, []] if deals.blank?

    contact_id_by_deal_id = contact_id_by_deal_id(deals)
    linked, external = deals.partition { |deal| contact_id_by_deal_id[deal['id']] }

    [linked.to_h { |deal| [contact_id_by_deal_id[deal['id']], deal['Stage']] }, external.pluck('Stage')]
  end

  def contact_id_by_deal_id(deals)
    deal_ids = deals.pluck('id')
    Contact.where(account_id: account.id)
           .where("additional_attributes -> 'external' ->> 'zoho_deal_id' IN (?)", deal_ids)
           .pluck(Arel.sql("additional_attributes -> 'external' ->> 'zoho_deal_id'"), :id)
           .to_h
  end

  def visita_efectiva_stages
    V2::Reports::SalesFunnelBuilder::VISITA_EFECTIVA_STAGES
  end

  def closed_won_stages
    V2::Reports::SalesFunnelBuilder::CLOSED_WON_STAGES
  end
end
