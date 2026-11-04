# Fase 22 (docs/investigacion-tesis-ia/27_IMPLEMENTACION_ATRIBUCION_FASE22.md): tabla separada,
# 1:1 con revenue_leads -- NO agrega columnas a revenue_leads para no ensuciar la tabla más
# consultada del dataset de ML con columnas mayormente nulas (solo aplica al subconjunto con
# social_lead_id poblado, ver Fase 17) y para no mezclar el ciclo de vida de una resolución
# asíncrona (reintentos, permisos que se resuelven después) con el de la sincronización de Zoho.
#
# fetched_at es NULLABLE a propósito (corrección pedida en Fase 22 §2): una fila puede crearse
# en estado "pendiente" antes de que exista ningún intento de consulta a Meta -- fetched_at solo
# se exige (a nivel de modelo, no de columna) cuando verification_status ya no es "pendiente".
class CreateRevenueLeadMetaAttributions < ActiveRecord::Migration[7.1]
  def change
    create_table :revenue_lead_meta_attributions do |t|
      t.bigint :account_id, null: false
      t.bigint :revenue_lead_id, null: false
      t.string :social_lead_id, null: false

      t.string :meta_ad_id
      t.string :meta_adset_id
      t.string :meta_campaign_id
      t.string :meta_form_id
      t.string :meta_ad_account_id
      t.datetime :meta_lead_created_at

      t.string :verification_status, null: false, default: 'pendiente'
      t.integer :fetch_error_code
      t.integer :fetch_error_subcode
      t.string :source, null: false, default: 'graph_api_leadgen_lookup'
      t.datetime :fetched_at

      t.timestamps
    end

    add_index :revenue_lead_meta_attributions, :revenue_lead_id, unique: true
    add_index :revenue_lead_meta_attributions, [:account_id, :verification_status]
    add_index :revenue_lead_meta_attributions, :meta_campaign_id
    add_index :revenue_lead_meta_attributions, :meta_adset_id
    add_index :revenue_lead_meta_attributions, :meta_ad_id
  end
end
