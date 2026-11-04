# Fase 22: evidencia de que una sincronización corrió y confirmó el importe vigente, incluso
# cuando no hubo cambio (y por lo tanto no se creó ninguna fila en revenue_ad_spend_revisions).
# Sin esto, una fila nunca re-sincronizada (gasto desactualizado) sería indistinguible de una
# confirmada como vigente la última vez que corrió el job.
class AddLastSyncedAtToRevenueAdSpends < ActiveRecord::Migration[7.1]
  def change
    add_column :revenue_ad_spends, :last_synced_at, :datetime
  end
end
