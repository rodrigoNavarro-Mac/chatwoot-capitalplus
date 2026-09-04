# Espejo analítico de un Zoho Deal. Poblada por RevenueIntelligence::SyncZohoDealsJob.
# won/lost se derivan estrictamente del picklist real de Stage (ver RevenueIntelligence::DealMapper)
# — "Apartado" NO es won, es intención fuerte previa al cierre.
class CreateRevenueDeals < ActiveRecord::Migration[7.1]
  def change
    create_table :revenue_deals do |table|
      add_identity_columns(table)
      add_pipeline_columns(table)
      add_outcome_columns(table)

      # Campos de cotización: existen en el payload de Zoho pero el MVP NO construye lógica
      # analítica sobre ellos (Precio_por_m2, Superficie, Descuento, Enganche, Plazos,
      # Meses_sin_intereses, Precio_a_Meses, Fecha_de_entrega, Tiene_el_presupuesto,
      # Productos_de_interes) — solo se preservan verbatim si vienen en el payload.
      table.jsonb :quote_fields, default: {}
      table.jsonb :raw_payload, default: {}
      table.datetime :synced_at

      table.timestamps
    end

    add_revenue_deal_indexes
  end

  private

  def add_identity_columns(table)
    table.bigint :account_id, null: false
    table.bigint :revenue_contact_id
    table.bigint :revenue_lead_id # lógico -> revenue_leads.id, best-effort, puede quedar null
    table.string :zoho_deal_id, null: false
    table.string :owner_id
    table.string :owner_name
    # OJO: el campo fuente en Zoho Deals es "Desarollo" (una sola erre — typo real y confirmado de
    # esta cuenta Zoho, distinto de "Desarrollo" en Leads). No "corregir" este mapeo sin verificar
    # contra la cuenta Zoho real primero.
    table.string :desarrollo
  end

  def add_pipeline_columns(table)
    table.string :stage
    table.string :pipeline
    table.decimal :probability, precision: 5, scale: 2
    table.decimal :amount, precision: 14, scale: 2
    table.decimal :expected_revenue, precision: 14, scale: 2
    table.string :lead_source
    table.string :campaign_source
    table.datetime :created_at_source
    table.datetime :stage_modified_at
    table.date :closing_date
  end

  def add_outcome_columns(table)
    table.boolean :won, null: false, default: false
    table.boolean :lost, null: false, default: false
    table.string :reason_for_loss
  end

  def add_revenue_deal_indexes
    add_index :revenue_deals, [:account_id, :zoho_deal_id], unique: true
    add_index :revenue_deals, [:account_id, :revenue_contact_id]
    add_index :revenue_deals, [:account_id, :revenue_lead_id]
    add_index :revenue_deals, [:account_id, :stage]
    add_index :revenue_deals, [:account_id, :desarrollo]
    add_index :revenue_deals, [:account_id, :won, :lost]
    add_index :revenue_deals, [:account_id, :stage_modified_at]
  end
end
