# Agregado dimensional genérico para Fase 3 — replica el patrón ya existente y probado de
# reporting_events_rollups (ver ReportingEvents::RollupService) en vez de crear una tabla nombrada
# por cada vista (funnel/agente/campaña/...). RevenueIntelligence::RefreshAggregatesJob la puebla
# vía upsert_all con ON CONFLICT (count/sum_value se ACUMULAN, nunca se reemplazan) — la única
# fuente de verdad para lo que la futura UI (Fase 5) va a leer; nunca se leen las tablas crudas
# directamente desde ahí.
#
# dimension_type/dimension_id/metric — convención documentada en el plan de Fase 3 ("Migraciones"):
#   funnel             -> dimension_id: desarrollo (o '_all')
#   agent              -> dimension_id: agent_id
#   campaign           -> dimension_id: campaign_id/adset_id/advert_id (filas separadas)
#   pipeline_stage     -> dimension_id: stage
#   call_conversion    -> dimension_id: clave compuesta (ej. "cta_used:true")
#   objection_conversion -> dimension_id: categoría de objeción
class CreateRevenueRollups < ActiveRecord::Migration[7.1]
  def change
    create_table :revenue_rollups do |table|
      table.bigint :account_id, null: false
      table.date :date, null: false
      table.string :dimension_type, null: false
      table.string :dimension_id, null: false
      table.string :metric, null: false
      table.integer :count, null: false, default: 0
      table.decimal :sum_value, precision: 14, scale: 2, null: false, default: 0

      table.timestamps
    end

    add_index :revenue_rollups, [:account_id, :date, :dimension_type, :dimension_id, :metric], unique: true,
                                                                                               name: 'idx_revenue_rollups_dedup'
    add_index :revenue_rollups, [:account_id, :dimension_type, :date]
  end
end
