# Campo separado de qualified_at (mirror crudo de Fecha_de_calificaci_n de Zoho) a propósito -- NO
# se puede sobreescribir qualified_at con una fecha inferida porque LeadMapper reasigna esa columna
# en CADA sync desde el payload crudo, así que cualquier inferencia ahí se perdería en la siguiente
# corrida horaria de SyncZohoLeadsJob.
#
# effective_qualified_at = qualified_at si existe, si no la fecha en que el deal alcanzó "Agendo
# cita" (o una etapa posterior) según Stage_History -- el equipo de ventas confirmó que ese campo
# de Zoho no siempre se llena antes de agendar una cita real, así que sin esto "Citas" podía superar
# a "Calificados" en el funnel (bug real reportado 2026-09-2X). Poblado por
# RevenueIntelligence::BuildEventsJob#update_effective_qualified_at.
class AddEffectiveQualifiedAtToRevenueLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :revenue_leads, :effective_qualified_at, :datetime
    add_index :revenue_leads, [:account_id, :effective_qualified_at]
  end
end
