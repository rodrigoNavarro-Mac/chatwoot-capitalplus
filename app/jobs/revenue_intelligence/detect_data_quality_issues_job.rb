# Reglas determinísticas de integridad del propio CRM/sincronización — no de negocio (eso es
# RevenueIntelligence::DetectRisksJob) — escribe/cierra filas en revenue_risk_signals
# (category: 'data_quality'). Ver el plan de Fase 4. Mismo comportamiento sin cursor incremental
# que DetectRisksJob: cada corrida reevalúa el universo completo, para poder auto-resolver señales
# cuya condición ya no aplica.
class RevenueIntelligence::DetectDataQualityIssuesJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(account_id = nil)
    hooks = Integrations::Hook.enabled.where(app_id: 'zoho_crm')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      build_for_account(hook.account)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::DetectDataQualityIssuesJob] account=#{hook.account_id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: hook.account).capture_exception
    end
  end

  private

  def build_for_account(account)
    recorder = RevenueIntelligence::RiskSignalRecorder.new(account, category: 'data_quality')

    detect_stage_mismatch(account, recorder, 'deal_won_stage_mismatch', won_column: :won, target_stage: RevenueDeal::WON_STAGE)
    detect_stage_mismatch(account, recorder, 'deal_lost_stage_mismatch', won_column: :lost, target_stage: RevenueDeal::LOST_STAGE)
    detect_deal_without_lead(account, recorder)
    detect_stage_event_gap(account, recorder)
    detect_unresolved_identity_conflicts(account, recorder)
  end

  # Contradicción entre el booleano derivado (won/lost) y el picklist real de Stage — debería ser
  # imposible si RevenueIntelligence::DealMapper funciona bien; existe para detectar corrupción de
  # datos o un cambio futuro no anticipado en el picklist de Zoho.
  def detect_stage_mismatch(account, recorder, signal_type, won_column:, target_stage:)
    mismatched = account.revenue_deals.where(won_column => true).where.not(stage: target_stage)
                        .or(account.revenue_deals.where(won_column => false).where(stage: target_stage))

    mismatched.find_each do |deal|
      recorder.record(signal_type: signal_type, subject_type: 'RevenueDeal', subject_id: deal.id, severity: 'high',
                      context: { 'stage' => deal.stage, won_column.to_s => deal[won_column] })
    end

    recorder.resolve_stale!(signal_type: signal_type, active_subject_ids: mismatched.ids)
  end

  # Vínculo best-effort que falló (ya documentado como riesgo aceptado en Fase 1) — aquí se vuelve
  # monitoreable, no se "arregla" automáticamente. severity baja: es informativo, no bloquea nada.
  def detect_deal_without_lead(account, recorder)
    deals = account.revenue_deals.where(revenue_lead_id: nil)

    deals.find_each do |deal|
      recorder.record(signal_type: 'deal_without_lead', subject_type: 'RevenueDeal', subject_id: deal.id, severity: 'low',
                      context: { 'zoho_deal_id' => deal.zoho_deal_id })
    end

    recorder.resolve_stale!(signal_type: 'deal_without_lead', active_subject_ids: deals.ids)
  end

  # Desfase entre el stage sincronizado en revenue_deals (cron :05) y el último
  # revenue_stage_events sincronizado (cron :15) — solo evalúa deals que YA tienen al menos una
  # fila de stage_history; si todavía no tiene ninguna, es "aún no sincronizado", no un gap.
  def detect_stage_event_gap(account, recorder)
    # Ordenado ascendente por entered_at y volcado a un hash: cada fila posterior pisa a la
    # anterior, así el hash final queda con el stage MÁS RECIENTE de cada deal sin necesitar una
    # segunda consulta.
    latest_stage_by_deal = account.revenue_stage_events.where.not(revenue_deal_id: nil).order(:entered_at)
                                  .pluck(:revenue_deal_id, :stage)
                                  .each_with_object({}) { |(deal_id, stage), acc| acc[deal_id] = stage }

    gapped = account.revenue_deals.where(id: latest_stage_by_deal.keys).reject { |deal| latest_stage_by_deal[deal.id] == deal.stage }

    gapped.each do |deal|
      recorder.record(signal_type: 'stage_event_gap', subject_type: 'RevenueDeal', subject_id: deal.id, severity: 'low',
                      context: { 'revenue_deals_stage' => deal.stage, 'last_stage_event_stage' => latest_stage_by_deal[deal.id] })
    end

    recorder.resolve_stale!(signal_type: 'stage_event_gap', active_subject_ids: gapped.map(&:id))
  end

  # Passthrough de RevenueIdentityConflict.unresolved — así la futura UI (Fase 5) lee una sola
  # tabla de "cosas pendientes" en vez de unir revenue_risk_signals + revenue_identity_conflicts.
  def detect_unresolved_identity_conflicts(account, recorder)
    conflicts = account.revenue_identity_conflicts.unresolved

    conflicts.find_each do |conflict|
      recorder.record(signal_type: 'unresolved_identity_conflict', subject_type: 'RevenueIdentityConflict', subject_id: conflict.id,
                      severity: 'medium', context: conflict.raw_context)
    end

    recorder.resolve_stale!(signal_type: 'unresolved_identity_conflict', active_subject_ids: conflicts.ids)
  end
end
