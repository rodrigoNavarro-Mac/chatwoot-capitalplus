# Una fila por cambio de etapa de un Deal, espejo del related list nativo de Zoho
# `Deals/{id}/Stage_History`. Poblada por RevenueIntelligence::SyncZohoStageHistoryJob.
# Doble estrategia de idempotencia porque la forma exacta del payload de Stage_History (si trae
# un id estable por fila) no está confirmada contra una muestra real todavía — ver riesgos del
# plan de Fase 1.
class CreateRevenueStageEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :revenue_stage_events do |table|
      add_identity_columns(table)
      add_stage_columns(table)

      table.jsonb :raw_payload, default: {}

      table.timestamps
    end

    add_revenue_stage_event_indexes
  end

  private

  def add_identity_columns(table)
    table.bigint :account_id, null: false
    table.string :zoho_deal_id, null: false
    table.bigint :revenue_deal_id
    table.bigint :revenue_contact_id # denormalizado desde revenue_deals al momento del sync
    # id del registro individual dentro del related list Stage_History de Zoho, si existe uno
    # estable — ver el índice compuesto de respaldo si no lo trae.
    table.string :zoho_history_id
    table.string :source_system, null: false, default: 'zoho_stage_history'
  end

  def add_stage_columns(table)
    table.string :stage, null: false
    table.string :previous_stage
    table.datetime :entered_at, null: false
    table.datetime :exited_at
    table.integer :duration_seconds
  end

  def add_revenue_stage_event_indexes
    # Ancla primaria de idempotencia si Zoho da un id estable por fila de historial.
    add_index :revenue_stage_events, [:account_id, :zoho_deal_id, :zoho_history_id],
              unique: true, where: 'zoho_history_id IS NOT NULL', name: 'idx_stage_events_on_history_id'
    # Respaldo si zoho_history_id no existe o no es confiable.
    add_index :revenue_stage_events, [:account_id, :zoho_deal_id, :stage, :entered_at],
              unique: true, where: 'zoho_history_id IS NULL', name: 'idx_stage_events_on_composite_key'
    add_index :revenue_stage_events, [:account_id, :revenue_deal_id]
    add_index :revenue_stage_events, [:account_id, :revenue_contact_id]
  end
end
