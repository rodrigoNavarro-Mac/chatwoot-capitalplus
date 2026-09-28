# Cuando el plazo de una cotización supera el umbral configurado para su desarrollo (ver
# QuoteDevelopmentRule), la cotización se puede generar igual pero queda "pending" y su PDF no se
# puede descargar hasta que alguien con permiso la apruebe explícitamente.
class AddAuthorizationToQuotes < ActiveRecord::Migration[7.1]
  def change
    add_column :quotes, :authorization_status, :string, null: false, default: 'not_required'
    add_column :quotes, :authorized_by_id, :bigint
    add_column :quotes, :authorized_at, :datetime

    add_index :quotes, [:account_id, :authorization_status]
  end
end
