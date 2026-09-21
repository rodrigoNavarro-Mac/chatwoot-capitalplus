# Inversión de Meta Ads capturada MANUALMENTE (no hay integración de costos de Meta ni API de
# spend disponible — confirmado en la auditoría de Fase 1 del tab Marketing). Tabla propia,
# separada de revenue_rollups a propósito: revenue_rollups se BORRA y RECONSTRUYE cada hora
# (RevenueIntelligence::RefreshAggregatesJob, RECHECK_WINDOW) porque es 100% derivada de Zoho — un
# dato capturado a mano ahí se perdería en la siguiente corrida.
#
# Sin campaign_id/adset_id/advert_id como llave: confirmado con el usuario que Zoho/Meta NUNCA
# entrega un ID real para esta cuenta, solo el nombre (ver RevenueIntelligence::LeadMapper
# comentario sobre Campa_a/Adset_Id/Advert_Id siempre nil) — el match contra revenue_leads/
# revenue_deals es por nombre. adset_name/advert_name son nullable a propósito: la captura puede
# ser solo a nivel campaña o campaña+adset (ver sección 10.1 del brief de producto).
class CreateRevenueAdSpends < ActiveRecord::Migration[7.1]
  def change
    create_table :revenue_ad_spends do |t|
      t.bigint :account_id, null: false
      t.string :desarrollo
      t.string :campaign_name, null: false
      t.string :adset_name
      t.string :advert_name
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.string :currency, null: false, default: 'MXN'
      t.bigint :created_by_id
      t.bigint :updated_by_id

      t.timestamps
    end

    add_index :revenue_ad_spends, [:account_id, :campaign_name, :adset_name, :advert_name, :period_start, :period_end],
              unique: true, name: 'idx_revenue_ad_spends_dedup'
    add_index :revenue_ad_spends, [:account_id, :period_start, :period_end]
  end
end
