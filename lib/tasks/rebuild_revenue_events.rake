namespace :chatwoot do
  desc 'Resetea el cursor "events" a nil y corre BuildEventsJob.perform_now para reconstruir ' \
       'revenue_events desde cero -- necesario tras el fix de BuildEventsJob#upsert_event (antes no ' \
       'actualizaba event_at/metadata de un evento ya existente cuando el dato de origen cambiaba, ' \
       'ej. la corrección de First_Contact_Time). Correr chatwoot:recompute_rollups DESPUÉS de este ' \
       'task -- los rollups de tipo funnel/agent se acumulan de forma aditiva y no se autocorrigen ' \
       'solo con revenue_events ya arreglado.' \
       "\nUso: ACCOUNT_ID=2 bin/rails chatwoot:rebuild_events"
  task rebuild_events: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    before = account.revenue_events.count

    RevenueSyncCursor.find_by(account_id: account.id, sync_type: 'events')&.update!(last_synced_at: nil)
    RevenueIntelligence::BuildEventsJob.perform_now(account.id)

    after = account.revenue_events.count
    puts "revenue_events: #{before} -> #{after} (cuenta #{account.id})."
  end
end
