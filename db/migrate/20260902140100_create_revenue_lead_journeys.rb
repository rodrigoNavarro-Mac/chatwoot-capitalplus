# Una fila por RevenueLead, con los hitos/tiempos-a-X/actividad agregados a partir de
# revenue_events — poblada por RevenueIntelligence::BuildJourneysJob. Es el resumen "listo para
# leer" del journey completo (Lead -> mensajes -> llamadas -> calificación -> Deal -> cita ->
# visita -> apartado -> ganado/perdido); la UI de fases futuras lee de aquí, no de revenue_events
# directamente.
class CreateRevenueLeadJourneys < ActiveRecord::Migration[7.1]
  def change
    create_table :revenue_lead_journeys do |table|
      add_identity_columns(table)
      add_milestone_columns(table)
      add_outcome_columns(table)
      add_time_to_columns(table)
      add_activity_columns(table)
      add_call_intelligence_columns(table)

      table.datetime :built_at
      table.timestamps
    end

    add_revenue_lead_journey_indexes
  end

  private

  def add_identity_columns(table)
    table.bigint :account_id, null: false
    table.bigint :revenue_lead_id, null: false
    table.bigint :revenue_contact_id
    table.bigint :revenue_deal_id
  end

  def add_milestone_columns(table)
    table.datetime :lead_created_at
    table.datetime :first_response_at
    table.datetime :first_call_at
    table.datetime :first_answered_call_at
    table.datetime :qualified_at
    table.datetime :deal_created_at
    table.datetime :appointment_at
    table.datetime :visit_at
    table.datetime :reserved_at
    table.datetime :closed_at
  end

  def add_outcome_columns(table)
    table.string :final_stage
    table.boolean :won, null: false, default: false
    table.boolean :lost, null: false, default: false
  end

  def add_time_to_columns(table)
    table.integer :time_to_first_response_seconds
    table.integer :time_to_first_call_seconds
    table.integer :time_to_qualification_seconds
    table.integer :time_to_appointment_seconds
    table.integer :time_to_visit_seconds
    table.integer :time_to_close_seconds
  end

  def add_activity_columns(table)
    table.integer :incoming_messages, null: false, default: 0
    table.integer :outgoing_messages, null: false, default: 0
    table.integer :calls_attempted, null: false, default: 0
    table.integer :calls_answered, null: false, default: 0
    table.integer :calls_missed, null: false, default: 0
    table.integer :total_call_seconds, null: false, default: 0
    table.integer :unique_agents, null: false, default: 0
  end

  def add_call_intelligence_columns(table)
    table.string :latest_intent
    table.string :max_intent
    table.decimal :avg_call_score, precision: 6, scale: 2
    table.decimal :max_call_score, precision: 6, scale: 2
    table.decimal :last_call_score, precision: 6, scale: 2
    table.integer :cta_count, null: false, default: 0
    table.integer :objections_count, null: false, default: 0
    table.integer :risks_count, null: false, default: 0
  end

  def add_revenue_lead_journey_indexes
    add_index :revenue_lead_journeys, [:account_id, :revenue_lead_id], unique: true
    add_index :revenue_lead_journeys, [:account_id, :revenue_contact_id]
    add_index :revenue_lead_journeys, [:account_id, :won, :lost]
    add_index :revenue_lead_journeys, [:account_id, :final_stage]
  end
end
