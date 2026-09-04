# Agrega la dimensión "desarrollo" como columna real (no embebida en dimension_id) a
# revenue_rollups, para poder filtrar TODA la página de Revenue Intelligence por desarrollo desde
# un selector global — hasta ahora solo la dimensión 'funnel' la traía (como el propio
# dimension_id, convención que NO se toca aquí por compatibilidad con datos ya acumulados en
# producción desde Fase 3). Default '_all' (nunca NULL) para que las queries de filtro no
# necesiten manejar NULL aparte — mismo valor de fallback que RefreshAggregatesJob#funnel_rows ya
# usa cuando no puede resolver un desarrollo real.
class AddDesarrolloToRevenueRollups < ActiveRecord::Migration[7.1]
  def change
    add_column :revenue_rollups, :desarrollo, :string, null: false, default: '_all'

    remove_index :revenue_rollups, column: %i[account_id date dimension_type dimension_id metric],
                                   name: 'idx_revenue_rollups_dedup'
    add_index :revenue_rollups, %i[account_id date dimension_type dimension_id metric desarrollo], unique: true,
                                                                                                   name: 'idx_revenue_rollups_dedup'
  end
end
