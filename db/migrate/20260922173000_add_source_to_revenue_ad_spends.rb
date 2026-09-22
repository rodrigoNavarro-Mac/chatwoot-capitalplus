# Distingue captura manual (equipo, vía MarketingSpendModal) de gasto sincronizado
# automáticamente desde Meta Marketing API (RevenueIntelligence::SyncMetaAdsSpendJob, ver
# Fase 2 del plan de integración con Meta Ads). Ver RevenueIntelligenceBuilder#spend_records_in_range
# para la regla de precedencia: "automático manda" sobre manual para la misma campaña, una vez
# que existe al menos un registro meta_api en el rango consultado (decisión explícita del
# usuario, no asumida).
class AddSourceToRevenueAdSpends < ActiveRecord::Migration[7.1]
  def change
    add_column :revenue_ad_spends, :source, :string, default: 'manual', null: false
    add_index :revenue_ad_spends, [:account_id, :campaign_name, :source]
  end
end
