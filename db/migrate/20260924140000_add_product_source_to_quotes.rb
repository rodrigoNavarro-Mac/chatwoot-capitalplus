# Las cotizaciones generadas desde el botón del módulo Cotizaciones ya no dependen de un Deal de
# Zoho: el usuario elige un Producto de Zoho CRM (un lote/unidad, reutilizable entre varios Deals)
# y puede editar todos los campos a mano antes (y después) de generar. zoho_deal_id pasa a ser
# opcional porque estas cotizaciones no tienen ningún Deal asociado.
class AddProductSourceToQuotes < ActiveRecord::Migration[7.1]
  def change
    change_column_null :quotes, :zoho_deal_id, true
    add_column :quotes, :zoho_product_id, :string
    add_column :quotes, :source_type, :string, null: false, default: 'deal'

    add_index :quotes, [:account_id, :zoho_product_id]
  end
end
