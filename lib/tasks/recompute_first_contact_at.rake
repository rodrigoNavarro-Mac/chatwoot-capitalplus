namespace :chatwoot do
  desc 'Recalcula revenue_leads.first_contact_at para leads YA sincronizados, bajo la nueva ' \
       'definición (RevenueIntelligence::LeadMapper#contacted_at: Lead_Status == "Contactado", ' \
       'no "el agente ya mandó un mensaje") -- necesario tras ese cambio para que aplique al ' \
       'histórico ya acumulado, no solo a corridas futuras del sync. No llama a la API de Zoho: ' \
       'todo el dato (Lead_Status/First_Contact_Time/Modified_Time) ya vive en raw_payload.' \
       "\nPor default solo IMPRIME cuántos leads cambiarían (dry run)." \
       "\nUso: ACCOUNT_ID=2 bin/rails chatwoot:recompute_first_contact_at" \
       "\nAgregar DRY_RUN=false para aplicar de verdad. Después de aplicar, correr " \
       'chatwoot:recompute_rollups para que el histórico de revenue_rollups también se actualice.'
  task recompute_first_contact_at: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    dry_run = ENV.fetch('DRY_RUN', 'true') != 'false'

    total = 0
    changed = 0

    account.revenue_leads.where.not(raw_payload: nil).find_each do |lead|
      total += 1
      new_value = RevenueIntelligence::LeadMapper.map(lead.raw_payload)[:first_contact_at]
      next if new_value&.to_i == lead.first_contact_at&.to_i

      changed += 1
      puts "lead=#{lead.id} zoho_lead_id=#{lead.zoho_lead_id} lead_status=#{lead.lead_status.inspect} " \
           "actual=#{lead.first_contact_at&.iso8601 || 'blank'} -> nuevo=#{new_value&.iso8601 || 'blank'}"
      lead.update!(first_contact_at: new_value) unless dry_run
    end

    puts "#{total} leads revisados, #{changed} con first_contact_at distinto bajo la nueva definición."
    if dry_run
      puts 'DRY RUN — no se escribió nada. Corre de nuevo con DRY_RUN=false para aplicar, luego ' \
           "ACCOUNT_ID=#{account.id} bin/rails chatwoot:recompute_rollups."
    end
  end
end
