# Fase 22 (docs/investigacion-tesis-ia/27_IMPLEMENTACION_ATRIBUCION_FASE22.md): snapshots
# versionados de metadatos de creativo. CORRECCIÓN explícita respecto al borrador de Fase 21: NO
# se guarda la respuesta cruda de Meta (`raw_payload` jsonb) -- la instrucción de Fase 22 §3 pide
# una lista permitida de campos, para no almacenar datos innecesarios que el creativo pudiera
# traer. Solo los campos explícitamente listados abajo.
#
# Append-only, sin unique index sobre meta_ad_id: un anuncio puede editarse (texto/imagen) sin
# cambiar de ad_id -- cada resolución guarda una fila nueva con su propio fetched_at; la versión
# vigente para un lead específico es la más cercana (sin pasarse) a su fecha de creación, mismo
# principio point-in-time que gobierna el resto del dataset de A/C desde la Fase 9.
class CreateRevenueAdCreativeSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :revenue_ad_creative_snapshots do |t|
      t.bigint :account_id, null: false
      t.string :meta_ad_id, null: false
      t.string :meta_adset_id
      t.string :meta_campaign_id

      # Lista permitida de campos (Fase 22 §3) -- nada fuera de esto se persiste.
      t.string :format
      t.string :media_type
      t.text :title
      t.text :body
      t.string :call_to_action_type
      t.string :creative_id

      t.datetime :fetched_at, null: false

      t.timestamps
    end

    add_index :revenue_ad_creative_snapshots, [:meta_ad_id, :fetched_at]
  end
end
