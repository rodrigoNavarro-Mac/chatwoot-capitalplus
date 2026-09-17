# Agrega el nombre real del Deal (Zoho Deal_Name) a revenue_deals — hasta ahora no se sincronizaba
# ningún campo de nombre para el Deal (a diferencia de owner_name/campaign_name/etc., ya presentes).
# Necesario para poder reconocer deals de uso interno para cotizar (ej. "Cotización Fuego",
# "Cotización Amura - 1 ITZA" — confirmados reales en Zoho 2026-09-17, sin cliente real detrás,
# usados por el equipo para armar cotizaciones) y excluirlos de Revenue Intelligence por patrón de
# nombre — ver RevenueDeal::INTERNAL_QUOTE_NAME_PREFIX.
class AddNameToRevenueDeals < ActiveRecord::Migration[7.1]
  def change
    add_column :revenue_deals, :name, :string
  end
end
