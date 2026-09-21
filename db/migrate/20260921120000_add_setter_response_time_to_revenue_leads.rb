# Soporta la métrica "tiempo de respuesta del setter" del tab Marketing (Fase 6). Deliberadamente
# separado de first_contact_at/contacted_at (ya validado en producción para Contact Rate, ver
# RevenueIntelligence::LeadMapper#contacted_at) — ese campo mide "¿Zoho considera al lead
# contactado?" (vía Lead_Status), mientras que first_human_contact_at mide específicamente el
# primer mensaje/llamada HUMANA rastreable en Chatwoot, con fines de SLA de respuesta. Poblado por
# RevenueIntelligence::CalculateSetterResponseTimeJob.
class AddSetterResponseTimeToRevenueLeads < ActiveRecord::Migration[7.1]
  def change
    change_table :revenue_leads, bulk: true do |t|
      t.datetime :first_human_contact_at
      t.string :first_human_contact_channel
      t.integer :first_human_response_seconds
      t.integer :first_human_response_business_seconds
    end

    add_index :revenue_leads, [:account_id, :first_human_contact_at]
  end
end
