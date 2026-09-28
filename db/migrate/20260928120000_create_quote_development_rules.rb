# Reglas configurables por desarrollo (Zoho "Desarrollo") que gobiernan la generación de
# cotizaciones — por ahora un solo umbral: hasta cuántos meses de plazo el plan se cotiza
# automáticamente a meses sin intereses (todo el plazo), y a partir de cuántos meses requiere
# autorización explícita antes de poder descargarse. Ver Quotes::CalculateAndAttachService.
class CreateQuoteDevelopmentRules < ActiveRecord::Migration[7.1]
  def change
    create_table :quote_development_rules do |t|
      t.bigint :account_id, null: false
      t.string :desarrollo, null: false
      t.integer :msi_auto_max_plazo, null: false

      t.timestamps
    end

    add_index :quote_development_rules, [:account_id, :desarrollo], unique: true
  end
end
