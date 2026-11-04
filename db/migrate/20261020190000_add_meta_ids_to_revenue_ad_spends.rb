# Fase 22 de la investigación de tesis IA (docs/investigacion-tesis-ia/27_IMPLEMENTACION_ATRIBUCION_FASE22.md):
# agrega los identificadores reales de Meta como columnas ADITIVAS, sin tocar campaign_name/
# adset_name/advert_name ni el índice único existente por nombre (idx_revenue_ad_spends_dedup) --
# ese índice sigue siendo la llave de deduplicación real (ver RevenueIntelligence::SyncMetaAdsSpendJob
# y el análisis de riesgos en Fase 22 §1: cambiar la llave de dedup a los IDs reescribiría
# campaign_name en filas históricas en cada resincronización y rompería el match por nombre que usa
# V2::Reports::RevenueIntelligenceBuilder contra los dimension_id de los rollups, generados a partir
# del nombre con el que se creó cada Lead/Deal). Los IDs se guardan como metadato adicional,
# consultable para des-fragmentar agregaciones futuras SIN mutar filas existentes.
class AddMetaIdsToRevenueAdSpends < ActiveRecord::Migration[7.1]
  def change
    add_column :revenue_ad_spends, :meta_ad_account_id, :string
    add_column :revenue_ad_spends, :meta_campaign_id, :string
    add_column :revenue_ad_spends, :meta_adset_id, :string
    add_column :revenue_ad_spends, :meta_ad_id, :string

    # No es unique -- varias filas (una por período) comparten el mismo meta_ad_id, y un
    # renombramiento histórico puede dejar dos filas con nombres distintos pero el mismo
    # meta_ad_id (ver Fase 22 §1) -- el índice sirve para agrupar/filtrar en consultas futuras,
    # no para deduplicar en la escritura.
    add_index :revenue_ad_spends, [:account_id, :meta_ad_id]
  end
end
