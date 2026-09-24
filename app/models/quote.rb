# == Schema Information
#
# Table name: quotes
#
#  id                  :bigint           not null, primary key
#  deal_snapshot       :jsonb            not null
#  desarrollo          :string
#  descuento_aplicado  :decimal(14, 2)
#  enganche_monto      :decimal(14, 2)
#  enganche_pct        :decimal(6, 3)
#  error_message       :string
#  fecha_entrega       :date
#  interes_pct         :decimal(6, 3)
#  lote                :string
#  meses_sin_intereses :integer
#  monto               :decimal(14, 2)
#  monto_base          :decimal(14, 2)
#  nombre              :string
#  pago_mensual        :decimal(14, 2)
#  plazos              :integer
#  precio_m2           :decimal(12, 2)
#  precio_m2_final     :decimal(14, 2)
#  precio_total        :decimal(14, 2)
#  render_payload      :jsonb            not null
#  schedule            :jsonb            not null
#  source_type         :string           default("deal"), not null
#  status              :string           default("pending"), not null
#  superficie          :decimal(12, 2)
#  trigger_source      :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  contact_id          :bigint
#  generated_by_id     :bigint
#  zoho_deal_id        :string
#  zoho_product_id     :string
#
# Indexes
#
#  index_quotes_on_account_id_and_contact_id       (account_id,contact_id)
#  index_quotes_on_account_id_and_created_at       (account_id,created_at)
#  index_quotes_on_account_id_and_status           (account_id,status)
#  index_quotes_on_account_id_and_zoho_deal_id     (account_id,zoho_deal_id)
#  index_quotes_on_account_id_and_zoho_product_id  (account_id,zoho_product_id)
#
# `schedule` guarda el desglose completo por periodo (interés/capital/saldo) aunque el PDF
# exportado solo muestre Periodo/Fecha/Pago (ver app/views/quotes/pdf.html.erb) — así el detalle
# queda consultable sin recalcular.
class Quote < ApplicationRecord
  belongs_to :account
  belongs_to :contact, optional: true
  belongs_to :generated_by, class_name: 'User', optional: true

  has_one_attached :pdf

  enum status: { pending: 'pending', completed: 'completed', failed: 'failed' }
  enum source_type: { deal: 'deal', product: 'product' }

  validates :zoho_deal_id, presence: true, if: -> { deal? }
  validates :zoho_product_id, presence: true, if: -> { product? }
  validates :trigger_source, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :filter_by_contact_id, ->(id) { where(contact_id: id) if id.present? }
end
