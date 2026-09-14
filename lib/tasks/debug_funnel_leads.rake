namespace :chatwoot do
  desc 'Imprime los zoho_lead_id exactos que el funnel cuenta como lead_created para un ' \
       'desarrollo y mes dados (misma lógica de atribución que RefreshAggregatesJob#funnel_rows: ' \
       'desarrollo del deal si existe, si no el del lead) -- para diffear contra un conteo real ' \
       'de Zoho y encontrar discrepancias exactas.' \
       "\nUso: ACCOUNT_ID=2 DESARROLLO=Fuego MONTH=2026-08 bin/rails chatwoot:debug_funnel_leads"
  task debug_funnel_leads: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    desarrollo = ENV.fetch('DESARROLLO')
    since = Time.find_zone!(RevenueIntelligence::TIMEZONE).parse("#{ENV.fetch('MONTH')}-01")
    until_at = since + 1.month

    lookups = RevenueIntelligence::DesarrolloResolver.lookups(account)

    ids = account.revenue_events.where(event_type: 'lead_created', event_at: since...until_at)
                 .pluck(:zoho_lead_id, :zoho_deal_id).filter_map do |zoho_lead_id, zoho_deal_id|
      resolved = RevenueIntelligence::DesarrolloResolver.resolve(lookups, zoho_lead_id: zoho_lead_id, zoho_deal_id: zoho_deal_id)
      zoho_lead_id if resolved == desarrollo
    end

    puts ids.sort.join(',')
    puts "TOTAL: #{ids.size}"
  end
end
