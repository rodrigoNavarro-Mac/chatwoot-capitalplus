# Tramos por regla de desarrollo — reemplaza el umbral único (msi_auto_max_plazo) por una lista
# ordenada de tramos, cada uno con su propio límite de meses, si aplica MSI y si requiere
# autorización. Permite reglas como "0-12 MSI libre, 13-24 MSI con autorización, 25+ con interés y
# autorización" en vez de un solo corte. Ver QuoteDevelopmentRule#tier_for.
class CreateQuoteDevelopmentRuleTiers < ActiveRecord::Migration[7.1]
  def change
    create_table :quote_development_rule_tiers do |t|
      t.bigint :quote_development_rule_id, null: false
      t.integer :hasta_meses
      t.boolean :msi, null: false, default: false
      t.boolean :requires_authorization, null: false, default: false

      t.timestamps
    end

    add_index :quote_development_rule_tiers, :quote_development_rule_id, name: 'index_quote_dev_rule_tiers_on_rule_id'
    add_index :quote_development_rule_tiers, [:quote_development_rule_id, :hasta_meses], unique: true,
                                                                                         name: 'index_quote_dev_rule_tiers_on_rule_id_and_hasta_meses'
  end
end
