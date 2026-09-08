require 'csv'

namespace :chatwoot do
  desc 'Exporta a CSV las citas agendadas y visitas efectivas de un desarrollo — nombre, correo, ' \
       'celular y UTMs de Meta Ads (campaign/adset/advert/platform) por registro. Lee ' \
       'exclusivamente de revenue_appointments/revenue_stage_events ya sincronizados (Fases 1-2), ' \
       'nunca llama a Zoho.' \
       "\nUso: ACCOUNT_ID=2 DESARROLLO=Fuego bin/rails chatwoot:export_citas_visitas" \
       "\nEscribe el CSV en /app/storage/citas_visitas_<desarrollo>.csv dentro del contenedor " \
       '(usa OUTPUT=/ruta/propia.csv para cambiar la salida).'
  task export_citas_visitas: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    desarrollo = ENV.fetch('DESARROLLO')
    output = ENV.fetch('OUTPUT', "/app/storage/citas_visitas_#{desarrollo.parameterize}.csv")

    lead_name = lambda do |lead|
      next nil unless lead

      payload = lead.raw_payload || {}
      "#{payload['First_Name']} #{payload['Last_Name']}".strip.presence
    end

    deal_name = lambda do |deal|
      deal && (deal.raw_payload || {})['Deal_Name']
    end

    row_for = lambda do |tipo, fecha, lead, deal, contact|
      {
        tipo: tipo,
        fecha: fecha&.in_time_zone('America/Cancun')&.strftime('%Y-%m-%d %H:%M'),
        nombre: lead_name.call(lead) || deal_name.call(deal),
        correo: contact&.email,
        celular: contact&.raw_phone,
        campaign: lead&.campaign_name,
        adset: lead&.adset_name,
        advert: lead&.advert_name,
        platform: lead&.platform
      }
    end

    rows = []

    account.revenue_appointments.includes(:revenue_contact, :revenue_deal).find_each do |appt|
      deal = appt.revenue_deal || (appt.zoho_deal_id.present? ? account.revenue_deals.find_by(zoho_deal_id: appt.zoho_deal_id) : nil)
      lead = appt.zoho_lead_id.present? ? account.revenue_leads.find_by(zoho_lead_id: appt.zoho_lead_id) : deal&.revenue_lead
      next unless (deal&.desarrollo || lead&.desarrollo) == desarrollo

      rows << row_for.call('Cita agendada', appt.starts_at, lead, deal, appt.revenue_contact)
    end

    visita_stages = V2::Reports::SalesFunnelBuilder::VISITA_EFECTIVA_STAGES
    account.revenue_stage_events.where(stage: visita_stages).includes(:revenue_deal, :revenue_contact).find_each do |ev|
      deal = ev.revenue_deal || account.revenue_deals.find_by(zoho_deal_id: ev.zoho_deal_id)
      lead = deal&.revenue_lead
      next unless (deal&.desarrollo || lead&.desarrollo) == desarrollo

      rows << row_for.call('Visita efectiva', ev.entered_at, lead, deal, ev.revenue_contact || deal&.revenue_contact)
    end

    rows.sort_by! { |r| r[:fecha].to_s }

    # BOM al inicio: sin él, Excel en Windows reinterpreta el UTF-8 como Windows-1252 y rompe
    # acentos/emojis (confirmado 2026-09-08: "Rodríguez" salía como "RodrÃ­guez").
    File.write(output, "\xEF\xBB\xBF")
    CSV.open(output, 'a') do |csv|
      csv << %w[tipo fecha nombre correo celular campaign adset advert platform]
      rows.each { |r| csv << r.values }
    end

    puts "#{rows.size} filas escritas en #{output} (cuenta #{account.id}, desarrollo #{desarrollo})."
  end
end
