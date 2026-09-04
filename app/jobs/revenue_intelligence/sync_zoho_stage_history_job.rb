# Sincroniza el related list `Deals/{id}/Stage_History` de Zoho -> revenue_stage_events, para
# cada RevenueDeal tocado desde el último cursor (sync_type "stage_history"). No hay endpoint de
# "todo el historial modificado en un rango" — es por-deal, N+1 por diseño (ver riesgos del plan
# de Fase 1). Por cada deal se recalculan TODAS sus filas de historial en cada corrida donde el
# deal fue tocado, en vez de intentar parchear incrementalmente (más simple y confiable dado el
# volumen bajo por-deal — ver RevenueIntelligence::StageHistoryBuilder).
class RevenueIntelligence::SyncZohoStageHistoryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(account_id = nil)
    hooks = Integrations::Hook.enabled.where(app_id: 'zoho_crm')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      sync_hook(hook)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::SyncZohoStageHistoryJob] hook=#{hook.id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: hook.account).capture_exception
    end
  end

  private

  def sync_hook(hook)
    account = hook.account
    cursor_service = RevenueIntelligence::SyncCursorService.new(account, 'stage_history')
    until_at = Time.current
    client = RevenueIntelligence::Zoho::StageHistoryClient.new(hook)

    touched_deals(account, cursor_service.since).find_each do |deal|
      sync_deal(client, deal)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::SyncZohoStageHistoryJob] deal=#{deal.id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: account).capture_exception
    end

    cursor_service.advance!(until_at)
  rescue StandardError => e
    cursor_service&.record_error!(e.message)
    raise
  end

  def touched_deals(account, since)
    scope = account.revenue_deals
    since ? scope.where('updated_at >= ?', since) : scope
  end

  def sync_deal(client, deal)
    rows = client.list(deal.zoho_deal_id)
    return if rows.empty?

    fallback_entered_at = deal.created_at_source || deal.synced_at || deal.created_at
    built = RevenueIntelligence::StageHistoryBuilder.build(rows, fallback_entered_at: fallback_entered_at)
    built.each { |attrs| upsert_stage_event(deal, attrs) }
  end

  def upsert_stage_event(deal, attrs)
    event = find_or_initialize_event(deal, attrs)
    event.assign_attributes(attrs.merge(revenue_deal_id: deal.id, revenue_contact_id: deal.revenue_contact_id))
    event.save!
  end

  # Ancla por zoho_history_id si Zoho lo dio; si no, por la clave compuesta de respaldo (ver
  # índices de la migración de revenue_stage_events).
  def find_or_initialize_event(deal, attrs)
    scope = deal.account.revenue_stage_events.where(zoho_deal_id: deal.zoho_deal_id)
    if attrs[:zoho_history_id].present?
      scope.find_or_initialize_by(zoho_history_id: attrs[:zoho_history_id])
    else
      scope.find_or_initialize_by(stage: attrs[:stage], entered_at: attrs[:entered_at])
    end
  end
end
