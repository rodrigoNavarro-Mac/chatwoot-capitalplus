# Tiempo hasta el primer INTENTO de llamada (sección "marcar" pedida por el equipo de marketing,
# sesión 2026-09-23) -- deliberadamente distinto de first_human_response_seconds/
# first_human_contact_at (que solo cuentan contacto REAL: WhatsApp humano o llamada COMPLETADA).
# Aquí cuenta cualquier llamada saliente del setter, sin importar si conectó o fue a buzón -- la
# idea explícita del usuario es medir "¿cuánto tarda el setter en intentar el contacto?", no si lo
# logró. Ver RevenueIntelligence::CalculateSetterResponseTimeJob#process_call_attempts.
class AddFirstCallAttemptToRevenueLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :revenue_leads, :first_call_attempt_at, :datetime
    add_column :revenue_leads, :first_call_attempt_seconds, :integer
    add_column :revenue_leads, :first_call_attempt_business_seconds, :integer
    add_index :revenue_leads, :first_call_attempt_at
  end
end
