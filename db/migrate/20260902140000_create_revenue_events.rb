# Un evento normalizado por cada señal relevante del journey (mensaje, llamada, análisis,
# cambio de stage, cita, hito de lead/deal) — poblada por RevenueIntelligence::BuildEventsJob a
# partir de tablas operativas de solo lectura (messages/calls/call_analyses) y de las tablas
# revenue_* ya sincronizadas en Fase 1. Un mismo registro origen (ej. un RevenueStageEvent en
# "Cerrado ganado") puede producir MÁS de una fila aquí (stage_changed + closed_won) — están
# separadas por event_type en la clave de dedup, así que no colisionan entre sí.
class CreateRevenueEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :revenue_events do |table|
      add_identity_columns(table)
      add_event_columns(table)

      table.jsonb :metadata, default: {}

      table.timestamps
    end

    add_revenue_event_indexes
  end

  private

  def add_identity_columns(table)
    table.bigint :account_id, null: false
    table.bigint :revenue_contact_id
    table.string :zoho_lead_id
    table.string :zoho_deal_id
    table.bigint :conversation_id # lógico -> conversations.id, solo lectura
    table.bigint :call_id # lógico -> calls.id, solo lectura
    table.bigint :agent_id # lógico -> users.id, solo lectura
  end

  def add_event_columns(table)
    table.string :event_type, null: false
    table.datetime :event_at, null: false
    # 'chatwoot_message' | 'chatwoot_call' | 'call_analysis' | 'revenue_lead' | 'revenue_deal' |
    # 'revenue_stage_event' | 'revenue_appointment' | 'conversation'
    table.string :source_system, null: false
    # id del registro origen, como string — cubre tanto ids bigint locales como ids de Zoho.
    table.string :source_id, null: false
  end

  def add_revenue_event_indexes
    # Ancla real de idempotencia: recalcular el mismo evento del mismo origen nunca duplica.
    add_index :revenue_events, [:account_id, :source_system, :event_type, :source_id], unique: true,
                                                                                       name: 'idx_revenue_events_dedup'
    add_index :revenue_events, [:account_id, :revenue_contact_id, :event_at]
    add_index :revenue_events, [:account_id, :event_type, :event_at]
    add_index :revenue_events, [:account_id, :conversation_id]
    add_index :revenue_events, [:account_id, :call_id]
  end
end
