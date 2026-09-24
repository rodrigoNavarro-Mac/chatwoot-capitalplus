# Cotizaciones de plan de pago para un Deal de Zoho CRM, generadas desde Chatwoot (reemplaza la
# función Deluge `crearCotizacionYEnviar` + Zoho Creator). Historial append-only a propósito: un
# mismo Deal puede recotizarse (renegociación de precio/plazo), igual que el botón original de
# Zoho creaba un registro nuevo en Zoho Creator cada vez — por eso NO hay unicidad en
# [account_id, zoho_deal_id].
#
# `schedule` guarda el desglose completo por periodo (interés/capital/saldo), aunque el PDF
# exportado solo muestre Periodo/Fecha/Pago — así queda consultable sin tener que recalcular.
# `deal_snapshot`/`render_payload` guardan lo que se leyó de Zoho y lo que se le mandó a renderizar,
# para poder auditar/reproducir un PDF viejo sin depender de que el Deal en Zoho no haya cambiado.
class CreateQuotes < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- lista de columnas de la tabla, no lógica
  def change
    create_table :quotes do |t|
      t.bigint :account_id, null: false
      t.bigint :contact_id
      t.bigint :generated_by_id
      t.string :zoho_deal_id, null: false
      t.string :trigger_source, null: false
      t.string :status, null: false, default: 'pending'
      t.string :error_message

      t.string :nombre
      t.string :lote
      t.string :desarrollo

      t.integer :plazos
      t.integer :meses_sin_intereses
      t.decimal :superficie, precision: 12, scale: 2
      t.decimal :precio_m2, precision: 12, scale: 2
      t.date :fecha_entrega

      t.decimal :monto_base, precision: 14, scale: 2
      t.decimal :descuento_aplicado, precision: 14, scale: 2
      t.decimal :monto, precision: 14, scale: 2
      t.decimal :enganche_pct, precision: 6, scale: 3
      t.decimal :enganche_monto, precision: 14, scale: 2
      t.decimal :interes_pct, precision: 6, scale: 3
      t.decimal :pago_mensual, precision: 14, scale: 2
      t.decimal :precio_total, precision: 14, scale: 2
      t.decimal :precio_m2_final, precision: 14, scale: 2

      t.jsonb :schedule, null: false, default: []
      t.jsonb :deal_snapshot, null: false, default: {}
      t.jsonb :render_payload, null: false, default: {}

      t.timestamps
    end

    add_index :quotes, [:account_id, :zoho_deal_id]
    add_index :quotes, [:account_id, :contact_id]
    add_index :quotes, [:account_id, :status]
    add_index :quotes, [:account_id, :created_at]
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
