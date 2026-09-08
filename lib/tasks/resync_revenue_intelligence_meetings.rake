namespace :chatwoot do
  desc 'Resetea el cursor de sync de Meetings (Events de Zoho) y corre un resync historico ' \
       'completo. Necesario porque BackfillService no incluye "meetings" en ' \
       'CHUNKABLE_SYNC_TYPES — el cron horario de SyncZohoMeetingsJob solo re-escanea deals/' \
       'leads tocados desde el ultimo cursor, asi que las citas de antes de que el cursor ' \
       'empezara a avanzar nunca se sincronizaron a revenue_appointments.' \
       "\nUso: ACCOUNT_ID=2 bin/rails chatwoot:resync_meetings"
  task resync_meetings: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    cursor = RevenueSyncCursor.find_by(account_id: account.id, sync_type: 'meetings')
    before = account.revenue_appointments.count

    cursor&.update!(last_synced_at: nil)
    RevenueIntelligence::SyncZohoMeetingsJob.perform_now(account.id)

    after = account.revenue_appointments.count
    puts "revenue_appointments: #{before} -> #{after} (cuenta #{account.id})."
  end
end
