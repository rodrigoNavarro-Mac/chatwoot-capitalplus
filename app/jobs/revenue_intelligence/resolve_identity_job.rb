# Corre al final de la cadena de sync (después de Leads/Deals/StageHistory/Meetings) — resuelve
# el revenue_contact_id de todo lo que quedó sin identidad resuelta. Puramente local (nunca llama
# a la API de Zoho), así que a diferencia de los Sync*Job no necesita su propio
# RevenueIntelligence::SyncCursorService: el filtro `revenue_contact_id: nil` ya es, por sí mismo,
# el "qué falta por procesar" — correr esto de nuevo es siempre seguro y barato.
class RevenueIntelligence::ResolveIdentityJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(account_id = nil)
    hooks = Integrations::Hook.enabled.where(app_id: 'zoho_crm')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      resolve_account(hook.account)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::ResolveIdentityJob] account=#{hook.account_id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: hook.account).capture_exception
    end
  end

  private

  def resolve_account(account)
    resolver = RevenueIntelligence::IdentityResolver.new(account)

    account.revenue_leads.where(revenue_contact_id: nil).find_each do |lead|
      resolver.resolve_for_lead(lead)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::ResolveIdentityJob] lead=#{lead.id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: account).capture_exception
    end

    account.revenue_deals.where(revenue_contact_id: nil).find_each do |deal|
      resolver.resolve_for_deal(deal)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::ResolveIdentityJob] deal=#{deal.id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: account).capture_exception
    end
  end
end
