namespace :chatwoot do
  desc 'Borra revenue_rollups de la cuenta, resetea su cursor a nil, y corre ' \
       'RefreshAggregatesJob.perform_now para recalcular todo desde cero -- necesario tras un ' \
       'cambio en como se calculan los rollups (ej. el fix de zona horaria de bucketing) para que ' \
       'aplique al histórico ya acumulado, no solo a corridas futuras.' \
       "\nUso: ACCOUNT_ID=2 bin/rails chatwoot:recompute_rollups"
  task recompute_rollups: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    before = account.revenue_rollups.count

    RevenueRollup.where(account_id: account.id).delete_all
    RevenueSyncCursor.find_by(account_id: account.id, sync_type: 'rollups')&.update!(last_synced_at: nil)
    RevenueIntelligence::RefreshAggregatesJob.perform_now(account.id)

    after = account.revenue_rollups.count
    puts "revenue_rollups: #{before} -> #{after} (cuenta #{account.id})."
  end
end
