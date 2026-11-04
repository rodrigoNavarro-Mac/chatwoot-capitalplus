# Fase 22 (docs/investigacion-tesis-ia/27_IMPLEMENTACION_ATRIBUCION_FASE22.md): historial de
# revisiones de `revenue_ad_spends.amount`. Resuelve la fuga temporal sutil ya documentada en
# Fase 16 §4: el job tiene una ventana de recorrección de 7 días (Meta ajusta el gasto reportado
# días después) y hoy no existe forma de saber qué valor se conocía en el T0 real de un lead --
# solo el valor final ya reajustado. `observed_at` es el único timestamp real que el sistema
# puede conocer con certeza: el momento en que RevenueIntelligence vio y guardó ese valor. No se
# inventa un campo separado para "cuándo Meta calculó el número" -- Meta no expone esa fecha en
# la respuesta de Insights, solo el período del reporte (period_start/period_end, que ya vive en
# la fila padre de revenue_ad_spends, nunca se duplica aquí).
#
# Append-only por diseño: se inserta una fila SOLO cuando el importe cambia de verdad respecto a
# la última revisión conocida (ver RevenueAdSpend#record_revision_if_changed) -- nunca en cada
# corrida del job. Evidencia de sincronizaciones exitosas SIN cambio de importe se guarda aparte,
# como revenue_ad_spends.last_synced_at (columna simple, ver migración siguiente), no como una
# revisión -- evita inflar esta tabla con miles de filas idénticas.
class CreateRevenueAdSpendRevisions < ActiveRecord::Migration[7.1]
  def change
    create_table :revenue_ad_spend_revisions do |t|
      t.bigint :account_id, null: false
      t.bigint :revenue_ad_spend_id, null: false
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.datetime :observed_at, null: false

      t.timestamps
    end

    add_index :revenue_ad_spend_revisions, [:revenue_ad_spend_id, :observed_at],
              name: 'idx_revenue_ad_spend_revisions_lookup'
  end
end
