require 'csv'

namespace :chatwoot do
  desc 'Exporta a CSV el desglose completo de leads que marketing pide de forma recurrente -- ' \
       'respaldo por SSH del mismo export ya disponible como botón en la UI de Revenue ' \
       'Intelligence (reutiliza V2::Reports::RevenueIntelligenceLeadsExportBuilder).' \
       "\nUso: ACCOUNT_ID=2 DESARROLLO=Fuego bin/rails chatwoot:export_leads" \
       "\nDESARROLLO es opcional (sin él, exporta todos). SINCE/UNTIL (YYYY-MM-DD, opcionales) " \
       'filtran por fecha de creación del lead.'
  task export_leads: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    desarrollo = ENV.fetch('DESARROLLO', nil)
    since = ENV.fetch('SINCE', nil).presence && Date.parse(ENV.fetch('SINCE')).beginning_of_day
    until_date = ENV.fetch('UNTIL', nil).presence && Date.parse(ENV.fetch('UNTIL')).end_of_day
    output = ENV.fetch('OUTPUT', "/app/storage/leads_#{desarrollo&.parameterize || 'todos'}.csv")

    params = { desarrollo: desarrollo, since: since&.to_i&.to_s, until: until_date&.to_i&.to_s }
    rows = V2::Reports::RevenueIntelligenceLeadsExportBuilder.new(account: account, params: params).build

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
