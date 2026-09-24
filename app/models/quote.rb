# == Schema Information
#
# Table name: quotes
#
#  id                   :bigint           not null, primary key
#  deal_snapshot         :jsonb            not null
#  descuento_aplicado    :decimal(14, 2)
#  desarrollo            :string
#  enganche_monto        :decimal(14, 2)
#  enganche_pct          :decimal(6, 3)
#  error_message         :string
#  fecha_entrega          :date
#  interes_pct           :decimal(6, 3)
#  lote                  :string
#  meses_sin_intereses   :integer
#  monto                 :decimal(14, 2)
#  monto_base            :decimal(14, 2)
#  nombre                :string
#  pago_mensual           :decimal(14, 2)
#  plazos                :integer
#  precio_m2              :decimal(12, 2)
#  precio_m2_final         :decimal(14, 2)
#  precio_total           :decimal(14, 2)
#  render_payload         :jsonb            not null
#  schedule               :jsonb            not null
#  status                :string           default("pending"), not null
#  superficie             :decimal(12, 2)
#  trigger_source          :string           not null
#  zoho_deal_id            :string           not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  contact_id               :bigint
#  generated_by_id          :bigint
#
# Cotización de plan de pago para un Deal de Zoho CRM. Reemplaza la función Deluge
# `crearCotizacionYEnviar` + Zoho Creator: Quotes::GenerateFromZohoDealService arma un registro por
# cada corrida (historial append-only, un Deal puede recotizarse).
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

  validates :zoho_deal_id, presence: true
  validates :trigger_source, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :filter_by_contact_id, ->(id) { where(contact_id: id) if id.present? }
end
