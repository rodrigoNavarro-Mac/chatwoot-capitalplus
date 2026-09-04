# Aplica reglas determinísticas de negocio (nunca ML) sobre lo ya sincronizado/agregado en Fases
# 1-3 y escribe/cierra filas en revenue_risk_signals (category: 'risk') — ver el plan de Fase 4.
# A diferencia del resto de Revenue Intelligence, NO usa RevenueIntelligence::SyncCursorService:
# cada corrida reevalúa el universo COMPLETO de candidatos de cada regla (aceptable al volumen
# actual de la cuenta), porque una señal de riesgo necesita poder CERRARSE sola en cuanto su
# condición deja de cumplirse — algo que un cursor de solo-avance no puede expresar.
class RevenueIntelligence::DetectRisksJob < ApplicationJob
  queue_as :scheduled_jobs

  # Umbral de días sin cambio de stage para un deal abierto — 'Apartado' tolera más tiempo
  # estancado que una etapa temprana (es intención fuerte previa al cierre, no un deal frío).
  STALLED_THRESHOLD_DAYS = { RevenueDeal::RESERVED_STAGE => 30, '_default' => 15 }.freeze
  LEAD_NO_CONTACT_HOURS = 24
  APPOINTMENT_GRACE_HOURS = 2 # no marcar citas que apenas terminaron

  def perform(account_id = nil)
    hooks = Integrations::Hook.enabled.where(app_id: 'zoho_crm')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      build_for_account(hook.account)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::DetectRisksJob] account=#{hook.account_id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: hook.account).capture_exception
    end
  end

  private

  def build_for_account(account)
    recorder = RevenueIntelligence::RiskSignalRecorder.new(account, category: 'risk')

    detect_deal_stalled(account, recorder)
    detect_lead_no_contact(account, recorder)
    detect_appointment_no_show_unverified(account, recorder)
  end

  # dimension_id: RevenueDeal#id. severity 'high' a partir del doble del umbral de su etapa.
  def detect_deal_stalled(account, recorder)
    deals = account.revenue_deals.open.where.not(stage_modified_at: nil)
    stalled = deals.select { |deal| stalled_days(deal) >= threshold_days(deal.stage) }

    stalled.each do |deal|
      days = stalled_days(deal)
      severity = days >= (threshold_days(deal.stage) * 2) ? 'high' : 'medium'
      recorder.record(signal_type: 'deal_stalled', subject_type: 'RevenueDeal', subject_id: deal.id, severity: severity,
                      context: { 'stage' => deal.stage, 'days_stalled' => days })
    end

    recorder.resolve_stale!(signal_type: 'deal_stalled', active_subject_ids: stalled.map(&:id))
  end

  def stalled_days(deal)
    ((Time.current - deal.stage_modified_at) / 1.day).round
  end

  def threshold_days(stage)
    STALLED_THRESHOLD_DAYS[stage] || STALLED_THRESHOLD_DAYS['_default']
  end

  # Un lead ya descartado (discard_reason presente) no necesita seguimiento — no se marca.
  def detect_lead_no_contact(account, recorder)
    candidates = account.revenue_leads.where(first_contact_at: nil, discard_reason: nil).where.not(created_at_source: nil)
                        .where(created_at_source: ..LEAD_NO_CONTACT_HOURS.hours.ago)

    candidates.find_each do |lead|
      hours = ((Time.current - lead.created_at_source) / 1.hour).round
      recorder.record(signal_type: 'lead_no_contact', subject_type: 'RevenueLead', subject_id: lead.id, severity: 'high',
                      context: { 'hours_since_created' => hours })
    end

    recorder.resolve_stale!(signal_type: 'lead_no_contact', active_subject_ids: candidates.ids)
  end

  # No filtra por revenue_appointments.status (picklist real de Zoho no verificado en ninguna fase
  # anterior — ver riesgos del plan de Fase 4); posibles falsos positivos de citas canceladas hasta
  # verificarlo. Solo evalúa citas con revenue_deal_id resuelto (sin deal vinculado no hay stage
  # events contra los que verificar la visita).
  def detect_appointment_no_show_unverified(account, recorder)
    cutoff = APPOINTMENT_GRACE_HOURS.hours.ago
    appointments = account.revenue_appointments.where.not(revenue_deal_id: nil).where.not(starts_at: nil).where(starts_at: ..cutoff)
    visited_at_by_deal = visited_stage_entered_ats(account)

    flagged = appointments.reject { |appointment| visited_after?(visited_at_by_deal, appointment) }

    flagged.each do |appointment|
      hours = ((Time.current - appointment.starts_at) / 1.hour).round
      recorder.record(signal_type: 'appointment_no_show_unverified', subject_type: 'RevenueAppointment', subject_id: appointment.id,
                      severity: 'medium', context: { 'hours_since_appointment' => hours })
    end

    recorder.resolve_stale!(signal_type: 'appointment_no_show_unverified', active_subject_ids: flagged.map(&:id))
  end

  def visited_stage_entered_ats(account)
    account.revenue_stage_events.where(stage: V2::Reports::SalesFunnelBuilder::VISITA_EFECTIVA_STAGES)
           .pluck(:revenue_deal_id, :entered_at).group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
  end

  def visited_after?(visited_at_by_deal, appointment)
    Array(visited_at_by_deal[appointment.revenue_deal_id]).any? { |entered_at| entered_at > appointment.starts_at }
  end
end
