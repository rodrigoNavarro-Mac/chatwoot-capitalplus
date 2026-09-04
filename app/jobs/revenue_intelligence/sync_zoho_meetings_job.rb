# Sincroniza Zoho Events (Meetings) -> revenue_appointments, para cada RevenueDeal/RevenueLead
# tocado desde el último cursor (sync_type "meetings"). Reutiliza Crm::Zoho::Api::MeetingsClient
# tal cual, sin modificarlo — por-registro (Deals|Leads/{id}/Events), N+1 por diseño, no hay
# endpoint de "todos los eventos modificados en un rango" confirmado.
#
# `verified` es siempre true: toda fila nace de un Zoho Event real. El campo `Resultado` del
# Event (picklist: No Show / Solicito Cotizacion / No le gusto / Reagendo — confirmado contra la
# cuenta real) se guarda en `status`; es la señal de outcome real de la cita, útil para fases
# futuras de "visita verificada" — Fase 1 solo la preserva, no construye lógica sobre ella todavía.
class RevenueIntelligence::SyncZohoMeetingsJob < ApplicationJob
  queue_as :scheduled_jobs

  EVENTS_PER_PAGE = 200

  def perform(account_id = nil)
    hooks = Integrations::Hook.enabled.where(app_id: 'zoho_crm')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      sync_hook(hook)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::SyncZohoMeetingsJob] hook=#{hook.id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: hook.account).capture_exception
    end
  end

  private

  def sync_hook(hook)
    account = hook.account
    cursor_service = RevenueIntelligence::SyncCursorService.new(account, 'meetings')
    since = cursor_service.since
    until_at = Time.current
    client = Crm::Zoho::Api::MeetingsClient.new(hook)

    sync_deal_events(client, account, since)
    sync_lead_events(client, account, since)

    cursor_service.advance!(until_at)
  rescue StandardError => e
    cursor_service&.record_error!(e.message)
    raise
  end

  def sync_deal_events(client, account, since)
    touched(account.revenue_deals, since).find_each do |deal|
      fetch_events(client, deal.zoho_deal_id, 'Deals').each { |event| upsert_appointment(account, event, deal_link(deal)) }
    rescue StandardError => e
      log_and_track(account, 'deal', deal.id, e)
    end
  end

  def sync_lead_events(client, account, since)
    touched(account.revenue_leads, since).find_each do |lead|
      fetch_events(client, lead.zoho_lead_id, 'Leads').each { |event| upsert_appointment(account, event, lead_link(lead)) }
    rescue StandardError => e
      log_and_track(account, 'lead', lead.id, e)
    end
  end

  def touched(scope, since)
    since ? scope.where('updated_at >= ?', since) : scope
  end

  def fetch_events(client, zoho_id, zoho_module)
    return [] if zoho_id.blank?

    client.list(zoho_id: zoho_id, zoho_module: zoho_module, per_page: EVENTS_PER_PAGE)
  end

  def deal_link(deal)
    { revenue_contact_id: deal.revenue_contact_id, zoho_deal_id: deal.zoho_deal_id, revenue_deal_id: deal.id, zoho_lead_id: nil }
  end

  def lead_link(lead)
    { revenue_contact_id: lead.revenue_contact_id, zoho_lead_id: lead.zoho_lead_id, zoho_deal_id: nil, revenue_deal_id: nil }
  end

  def upsert_appointment(account, event, link)
    zoho_event_id = event['id']
    return if zoho_event_id.blank?

    appointment = account.revenue_appointments.find_or_initialize_by(zoho_event_id: zoho_event_id)
    appointment.assign_attributes(linkage_updates(appointment, link))
    appointment.assign_attributes(event_attrs(event))
    appointment.save!
  end

  # El mismo Event puede descubrirse vía su Lead en una corrida y vía el Deal convertido en otra
  # (o al revés) — nunca se sobrescribe zoho_deal_id/revenue_deal_id/zoho_lead_id/
  # revenue_contact_id con nil solo porque ESTA llamada no trae ese dato; se conserva lo que ya
  # había si la llamada actual no lo provee.
  def linkage_updates(appointment, link)
    {
      revenue_contact_id: link[:revenue_contact_id] || appointment.revenue_contact_id,
      zoho_lead_id: link[:zoho_lead_id] || appointment.zoho_lead_id,
      zoho_deal_id: link[:zoho_deal_id] || appointment.zoho_deal_id,
      revenue_deal_id: link[:revenue_deal_id] || appointment.revenue_deal_id
    }
  end

  def event_attrs(event)
    {
      owner_id: event.dig('Owner', 'id'),
      owner_name: event.dig('Owner', 'name'),
      starts_at: parse_time(event['Start_DateTime']),
      ends_at: parse_time(event['End_DateTime']),
      status: event['Resultado'],
      subject: event['Event_Title'],
      verified: true,
      raw_payload: event,
      synced_at: Time.current
    }
  end

  def log_and_track(account, kind, id, error)
    Rails.logger.error("[RevenueIntelligence::SyncZohoMeetingsJob] #{kind}=#{id} error=#{error.message}")
    ChatwootExceptionTracker.new(error, account: account).capture_exception
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
