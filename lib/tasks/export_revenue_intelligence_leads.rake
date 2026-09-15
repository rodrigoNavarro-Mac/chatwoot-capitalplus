require 'csv'

namespace :chatwoot do
  desc 'Exporta a CSV el desglose completo de leads que marketing pide de forma recurrente: fecha ' \
       'de creación, campaña/adset/advert, estado, si contestó, qué plantillas de WhatsApp se le ' \
       'mandaron, si ya calificó/se descartó, y si ya es Deal (etapa, ganado, cuánto tiempo pasó).' \
       "\nUso: ACCOUNT_ID=2 DESARROLLO=Fuego bin/rails chatwoot:export_leads" \
       "\nDESARROLLO es opcional (sin él, exporta todos). SINCE/UNTIL (YYYY-MM-DD, opcionales) " \
       'filtran por fecha de creación del lead.'
  task export_leads: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    desarrollo = ENV.fetch('DESARROLLO', nil)
    since = ENV.fetch('SINCE', nil).presence && Date.parse(ENV.fetch('SINCE'))
    until_date = ENV.fetch('UNTIL', nil).presence && Date.parse(ENV.fetch('UNTIL'))
    output = ENV.fetch('OUTPUT', "/app/storage/leads_#{desarrollo&.parameterize || 'todos'}.csv")

    days_between = lambda do |from, to|
      next nil if from.blank? || to.blank?

      ((to - from) / 1.day).round
    end

    deal_columns = lambda do |lead, deal|
      next { es_deal: 'No', etapa_deal: nil, ganado: nil, dias_lead_a_deal: nil, dias_deal_activo: nil } if deal.blank?

      ganado = if deal.won
                 'Sí'
               else
                 deal.lost ? 'No' : 'En curso'
               end

      {
        es_deal: 'Sí',
        etapa_deal: deal.stage,
        ganado: ganado,
        dias_lead_a_deal: days_between.call(lead.created_at_source, deal.created_at_source),
        dias_deal_activo: days_between.call(deal.created_at_source, Time.current)
      }
    end

    lead_row = lambda do |lead, templates_by_contact|
      deal = lead.revenue_deals.max_by(&:created_at_source)
      chatwoot_contact_id = lead.revenue_contact&.chatwoot_contact_id
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
        contestado: lead.first_contact_at.present? ? 'Sí' : 'No',
        fecha_primer_contacto: lead.first_contact_at&.strftime('%Y-%m-%d %H:%M'),
        plantillas_enviadas: (templates_by_contact[chatwoot_contact_id] || []).join(', '),
        calificado: lead.qualified_at.present? ? 'Sí' : 'No',
        descartado: lead.discard_reason.present? ? 'Sí' : 'No',
        razon_descarte: lead.discard_reason,
        **deal_columns.call(lead, deal)
      }
    end

    # { chatwoot_contact_id => ["Plantilla A", "Plantilla B", ...] } -- una sola consulta para
    # todos los leads en vez de N+1 por lead, mismo patrón que backfill_first_contact_time.rake.
    templates_sent_by_contact = lambda do |leads|
      contact_ids = leads.filter_map { |lead| lead.revenue_contact&.chatwoot_contact_id }.uniq
      next {} if contact_ids.empty?

      Message.joins(:conversation)
             .where(conversations: { contact_id: contact_ids, account_id: account.id })
             .outgoing.where("messages.content_attributes->'template_params' is not null")
             .pluck('conversations.contact_id', Arel.sql("messages.content_attributes->'template_params'->>'name'"))
             .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(cid, name), acc| acc[cid] << name if name.present? }
             .transform_values { |names| names.uniq.sort }
    end

    scope = account.revenue_leads.includes(:revenue_contact, :revenue_deals)
    scope = scope.where(desarrollo: desarrollo) if desarrollo.present?
    scope = scope.where(created_at_source: since..) if since
    scope = scope.where(created_at_source: ..until_date.end_of_day) if until_date
    leads = scope.to_a

    templates_by_contact = templates_sent_by_contact.call(leads)
    rows = leads.map { |lead| lead_row.call(lead, templates_by_contact) }

    # BOM al inicio: sin él, Excel en Windows reinterpreta el UTF-8 como Windows-1252.
    File.write(output, "\xEF\xBB\xBF")
    CSV.open(output, 'a') do |csv|
      csv << %w[zoho_lead_id nombre fecha_creacion desarrollo campaign adset advert lead_source estado
                contestado fecha_primer_contacto plantillas_enviadas calificado descartado razon_descarte
                es_deal etapa_deal ganado dias_lead_a_deal dias_deal_activo]
      rows.each { |r| csv << r.values }
    end

    puts "#{rows.size} leads escritos en #{output} (cuenta #{account.id}, desarrollo #{desarrollo || 'todos'})."
  end
end
