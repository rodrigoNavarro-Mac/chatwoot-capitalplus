namespace :chatwoot do
  desc 'Compara, para cada lead con first_contact_at, ese valor actual contra el event_at de su ' \
       'evento lead_contacted en revenue_events -- detecta eventos con timestamp desactualizado ' \
       '(bug real: BuildEventsJob antes no actualizaba event_at de un evento ya existente cuando el ' \
       'dato de origen cambiaba, ej. la corrección de First_Contact_Time) y leads contactados sin ' \
       'evento (revenue_contact_id no resuelto cuando corrió BuildEventsJob por última vez).' \
       "\nUso: ACCOUNT_ID=2 [DESARROLLO=Fuego] bin/rails chatwoot:diagnose_lead_contacted_drift"
  task diagnose_lead_contacted_drift: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    desarrollo = ENV.fetch('DESARROLLO', nil)

    leads = account.revenue_leads.where.not(first_contact_at: nil)
    leads = leads.where(desarrollo: desarrollo) if desarrollo.present?
    lead_rows = leads.pluck(:id, :first_contact_at)

    events = account.revenue_events.where(source_system: 'revenue_lead', event_type: 'lead_contacted',
                                          source_id: lead_rows.map { |id, _| id.to_s })
                    .pluck(:source_id, :event_at).to_h.transform_keys(&:to_i)

    missing = lead_rows.reject { |id, _| events.key?(id) }
    stale = lead_rows.select { |id, first_contact_at| events[id] && (events[id] - first_contact_at).abs > 1 }

    puts "leads con first_contact_at#{desarrollo.present? ? " (desarrollo=#{desarrollo})" : ''}: #{lead_rows.size}"
    puts "sin evento lead_contacted: #{missing.size}"
    puts "evento con event_at distinto al first_contact_at actual: #{stale.size}"
    puts "muestra sin evento (lead ids): #{missing.first(5).map(&:first)}" if missing.any?
    puts "muestra desactualizados (lead id, first_contact_at real): #{stale.first(5)}" if stale.any?
  end
end
