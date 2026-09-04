# Espejo de un Zoho Event (Meetings) real vinculado a un Lead/Deal. Poblada por
# RevenueIntelligence::SyncZohoMeetingsJob. `verified` existe para que fases futuras puedan
# distinguir explícitamente una cita verificada (esta tabla) de una señal débil/manual como el
# Stage "Agendo cita - Videollamada" sin Event real — ese Stage por sí solo NUNCA produce una fila
# aquí ("no inventar evidencia").
class CreateRevenueAppointments < ActiveRecord::Migration[7.1]
  def change
    create_table :revenue_appointments do |table|
      add_identity_columns(table)
      add_schedule_columns(table)

      table.jsonb :raw_payload, default: {}
      table.datetime :synced_at

      table.timestamps
    end

    add_revenue_appointment_indexes
  end

  private

  def add_identity_columns(table)
    table.bigint :account_id, null: false
    table.bigint :revenue_contact_id
    table.string :zoho_event_id, null: false
    table.string :zoho_lead_id
    table.string :zoho_deal_id
    table.bigint :revenue_deal_id
    table.string :owner_id
    table.string :owner_name
  end

  def add_schedule_columns(table)
    table.datetime :starts_at
    table.datetime :ends_at
    table.string :status
    table.string :subject
    # Siempre true en Fase 1: toda fila nace de un Zoho Event real vía SyncZohoMeetingsJob. La
    # columna existe para que Fase 2+ pueda modelar señales débiles sin mezclarlas en esta tabla.
    table.boolean :verified, null: false, default: true
  end

  def add_revenue_appointment_indexes
    add_index :revenue_appointments, [:account_id, :zoho_event_id], unique: true
    add_index :revenue_appointments, [:account_id, :revenue_contact_id]
    add_index :revenue_appointments, [:account_id, :revenue_deal_id]
    add_index :revenue_appointments, [:account_id, :zoho_deal_id]
    add_index :revenue_appointments, [:account_id, :starts_at]
  end
end
