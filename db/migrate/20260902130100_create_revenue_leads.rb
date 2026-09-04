# Espejo analítico de un Zoho Lead — una fila por lead sincronizado, independiente de a qué
# desarrollo pertenezca (el data mart soporta multi-desarrollo desde el día uno, aunque el MVP
# solo se valide con Fuego). Poblada por RevenueIntelligence::SyncZohoLeadsJob; revenue_contact_id
# queda null hasta que RevenueIntelligence::ResolveIdentityJob lo resuelve.
class CreateRevenueLeads < ActiveRecord::Migration[7.1]
  def change
    create_table :revenue_leads do |table|
      add_identity_columns(table)
      add_qualification_columns(table)
      add_budget_columns(table)
      add_marketing_columns(table)
      add_traceability_columns(table)

      table.jsonb :raw_payload, default: {} # payload crudo de Zoho, para auditoría/re-parseo
      table.datetime :synced_at

      table.timestamps
    end

    add_revenue_lead_indexes
  end

  private

  def add_identity_columns(table)
    table.bigint :account_id, null: false
    table.bigint :revenue_contact_id
    table.string :zoho_lead_id, null: false
    table.string :owner_id
    table.string :owner_name
    table.string :desarrollo
  end

  def add_qualification_columns(table)
    table.datetime :created_at_source
    table.datetime :first_contact_at
    table.datetime :qualified_at
    # Se guarda VERBATIM en español, tal como lo devuelve Zoho para esta cuenta (ej. "Contactado",
    # "Cliente perdido/Descartado") — sin canonicalizar a enum en Fase 1, eso es de una fase
    # posterior, no de Fundaciones.
    table.string :lead_status
    table.string :discard_reason
    table.string :razon_compra
    table.string :plazo
    table.string :genero
    table.string :ocupacion
    table.string :estado_civil
    table.string :etapa_vida
    table.string :nacionalidad
    table.string :rango_edad
  end

  # Presupuesto es texto libre en Zoho: el valor original SIEMPRE se conserva en presupuesto_raw;
  # min/max son un parseo heurístico best-effort (ver RevenueIntelligence::BudgetParser) y pueden
  # quedar null sin que eso sea un bug.
  def add_budget_columns(table)
    table.string :presupuesto_raw
    table.decimal :presupuesto_min, precision: 14, scale: 2
    table.decimal :presupuesto_max, precision: 14, scale: 2
  end

  def add_marketing_columns(table)
    table.string :lead_source
    table.string :campaign_id
    table.string :campaign_name
    table.string :ad_account_id
    table.string :ad_account_name
    table.string :adset_id
    table.string :adset_name
    table.string :advert_id
    table.string :advert_name
    table.string :form_id
    table.string :form_name
    table.string :platform
  end

  def add_traceability_columns(table)
    table.integer :attempt_count, null: false, default: 0
    table.integer :reassignment_count, null: false, default: 0
  end

  def add_revenue_lead_indexes
    add_index :revenue_leads, [:account_id, :zoho_lead_id], unique: true
    add_index :revenue_leads, [:account_id, :revenue_contact_id]
    add_index :revenue_leads, [:account_id, :desarrollo]
    add_index :revenue_leads, [:account_id, :lead_status]
    add_index :revenue_leads, [:account_id, :owner_id]
    add_index :revenue_leads, [:account_id, :created_at_source]
  end
end
