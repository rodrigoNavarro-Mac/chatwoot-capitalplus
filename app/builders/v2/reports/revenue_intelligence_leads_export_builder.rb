# Desglose completo de leads para exportar a CSV (pedido recurrente de marketing, ver
# lib/tasks/export_revenue_intelligence_leads.rake, que reutiliza esta misma clase para no
# duplicar la lógica entre el botón de la UI y el rake task de respaldo). Una fila por lead: fecha
# de creación, campaña/adset/advert, estado, si contestó, qué plantillas de WhatsApp se le
# mandaron, si calificó/descartó, y si ya es Deal (etapa, ganado, tiempos).
class V2::Reports::RevenueIntelligenceLeadsExportBuilder
  include DateRangeHelper

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    templates_by_contact = templates_sent_by_contact
    leads.map { |lead| lead_row(lead, templates_by_contact) }
  end

  private

  attr_reader :account, :params

  def leads
    @leads ||= begin
      scope = account.revenue_leads.includes(:revenue_contact, :revenue_deals)
      scope = scope.where(desarrollo: desarrollo_filter) if desarrollo_filter.present?
      scope = scope.where(created_at_source: range) if range
      scope.order(created_at_source: :desc).to_a
    end
  end

  def desarrollo_filter
    params[:desarrollo].presence
  end

  # { chatwoot_contact_id => ["Plantilla A", "Plantilla B", ...] } -- una sola consulta para todos
  # los leads en vez de N+1 por lead.
  # Mismo campo/patrón que V2::Reports::TemplatesReportBuilder (Message#additional_attributes.
  # template_params) -- ahí ya se documentó que este es el único rastro necesario, sin importar
  # si la plantilla se mandó por la bienvenida automática de Zoho o un paso de Cadencia.
  def templates_sent_by_contact
    contact_ids = leads.filter_map { |lead| lead.revenue_contact&.chatwoot_contact_id }.uniq
    return {} if contact_ids.empty?

    Message.joins(:conversation)
           .where(conversations: { contact_id: contact_ids, account_id: account.id })
           .where("messages.additional_attributes -> 'template_params' ->> 'name' IS NOT NULL")
           .pluck('conversations.contact_id', Arel.sql("messages.additional_attributes -> 'template_params' ->> 'name'"))
           .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(contact_id, name), acc| acc[contact_id] << name if name.present? }
           .transform_values { |names| names.uniq.sort }
  end

  def lead_row(lead, templates_by_contact)
    deal = lead.revenue_deals.max_by(&:created_at_source)
    payload = lead.raw_payload || {}

    {
      zoho_lead_id: lead.zoho_lead_id,
      nombre: "#{payload['First_Name']} #{payload['Last_Name']}".strip.presence,
      fecha_creacion: lead.created_at_source&.strftime('%Y-%m-%d %H:%M'),
      desarrollo: lead.desarrollo,
      campaign: lead.campaign_name,
      adset: lead.adset_name,
      advert: lead.advert_name,
      lead_source: lead.lead_source,
      estado: lead.lead_status,
      **contact_columns(lead, templates_by_contact),
      **deal_columns(lead, deal)
    }
  end

  def contact_columns(lead, templates_by_contact)
    chatwoot_contact_id = lead.revenue_contact&.chatwoot_contact_id

    {
      contestado: lead.first_contact_at.present? ? 'Sí' : 'No',
      fecha_primer_contacto: lead.first_contact_at&.strftime('%Y-%m-%d %H:%M'),
      plantillas_enviadas: (templates_by_contact[chatwoot_contact_id] || []).join(', '),
      calificado: lead.qualified_at.present? ? 'Sí' : 'No',
      descartado: lead.discard_reason.present? ? 'Sí' : 'No',
      razon_descarte: lead.discard_reason
    }
  end

  def deal_columns(lead, deal)
    return { es_deal: 'No', etapa_deal: nil, ganado: nil, dias_lead_a_deal: nil, dias_deal_activo: nil } if deal.blank?

    ganado = if deal.won
               'Sí'
             else
               deal.lost ? 'No' : 'En curso'
             end

    {
      es_deal: 'Sí',
      etapa_deal: deal.stage,
      ganado: ganado,
      dias_lead_a_deal: days_between(lead.created_at_source, deal.created_at_source),
      dias_deal_activo: days_between(deal.created_at_source, Time.current)
    }
  end

  def days_between(from, to)
    return nil if from.blank? || to.blank?

    ((to - from) / 1.day).round
  end
end
