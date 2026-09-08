# Acciones de escritura para la pestaña "Calidad de datos" de Revenue Intelligence — separado de
# ReportsController (que es de solo lectura) a propósito. Mismo gate que el resto de Revenue
# Intelligence (ReportPolicy#view?, ya exige administrador — ver decisión de alcance de Fase 1).
class Api::V2::Accounts::RevenueIntelligenceController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  SYNC_NOW_THROTTLE = 10.minutes

  # Deuda documentada desde Fase 1 (RevenueIntelligence::IdentityResolver): un conflicto de
  # identidad (mismo teléfono/email apuntando a revenue_contacts distintos) nunca se fusiona
  # solo, queda para revisión manual. Esta acción NO fusiona nada tampoco — solo registra que un
  # humano ya lo revisó (en Zoho, fuera de esta app) y puede dejar de aparecer como pendiente.
  def resolve_identity_conflict
    conflict = Current.account.revenue_identity_conflicts.find(params[:id])
    conflict.update!(resolved: true, resolved_at: Time.current)
    resolve_open_signal(signal_type: 'unresolved_identity_conflict', subject_type: 'RevenueIdentityConflict', subject_id: conflict.id)
    render json: { resolved: true }
  end

  # Reintenta el vínculo revenue_deals.revenue_lead_id -> revenue_leads LOCALMENTE (sin llamar a
  # Zoho): busca, entre los leads ya sincronizados, uno cuyo Converted_Deal apunte a este deal —
  # cubre el caso real más común (el lead se sincronizó antes de que el deal existiera localmente,
  # ver RevenueIntelligence::SyncZohoLeadsJob#link_converted_deal). Si no aparece, el lead de
  # origen probablemente no se ha sincronizado todavía — no dispara un backfill completo desde
  # aquí, eso sigue siendo tarea exclusiva del rake de backfill.
  def relink_deal
    deal = Current.account.revenue_deals.find(params[:id])
    return render json: { linked: true } if deal.revenue_lead_id.present?

    lead = Current.account.revenue_leads.find_by("raw_payload -> 'Converted_Deal' ->> 'id' = ?", deal.zoho_deal_id)
    return render json: { linked: false } if lead.blank?

    deal.update!(revenue_lead_id: lead.id)
    RevenueIntelligence::DealAttributionCopier.copy(deal: deal, lead: lead)
    RevenueIntelligence::IdentityResolver.new(Current.account).resolve_for_deal(deal)
    resolve_open_signal(signal_type: 'deal_without_lead', subject_type: 'RevenueDeal', subject_id: deal.id)
    render json: { linked: true }
  end

  # Dispara los 2 jobs de sync de Zoho (Leads/Deals) de Fase 1 de forma asíncrona, para no obligar
  # al usuario a pedir un comando de SSH cada vez que sospecha que faltan datos por sincronizar.
  # Throttle vía Rails.cache (mismo patrón ya usado en FetchImapEmailsJob) para no agotar los
  # créditos de API de Zoho si alguien le da clic varias veces seguidas (ver riesgo de rate
  # limiting documentado en el plan de Fase 1).
  def sync_now
    throttle_key = "revenue_intelligence_sync_now:#{Current.account.id}"
    return render json: { queued: false, reason: 'throttled' }, status: :too_many_requests if Rails.cache.exist?(throttle_key)

    RevenueIntelligence::SyncZohoLeadsJob.perform_later(Current.account.id)
    RevenueIntelligence::SyncZohoDealsJob.perform_later(Current.account.id)
    Rails.cache.write(throttle_key, true, expires_in: SYNC_NOW_THROTTLE)
    render json: { queued: true }
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  def resolve_open_signal(signal_type:, subject_type:, subject_id:)
    Current.account.revenue_risk_signals.open
           .find_by(signal_type: signal_type, subject_type: subject_type, subject_id: subject_id)
           &.update!(resolved_at: Time.current)
  end
end
