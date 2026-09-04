# Bookkeeping de "hasta qué Modified_Time ya sincronicé" por cuenta y tipo de sync — necesario
# para que la sincronización incremental (RevenueIntelligence::SyncZohoLeadsJob y hermanos) sea
# idempotente sin re-escanear todo Zoho en cada corrida. El cursor solo avanza si el job
# correspondiente terminó sin excepción (ver RevenueIntelligence::SyncCursorService).
class CreateRevenueSyncCursors < ActiveRecord::Migration[7.1]
  def change
    create_table :revenue_sync_cursors do |table|
      table.bigint :account_id, null: false
      table.string :sync_type, null: false # 'leads' | 'deals' | 'stage_history' | 'meetings'
      table.datetime :last_synced_at
      table.string :last_run_status
      table.text :last_error

      table.timestamps
    end

    add_index :revenue_sync_cursors, [:account_id, :sync_type], unique: true
  end
end
