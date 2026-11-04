# Atribución determinística Lead->anuncio vía `social_lead_id` (confirmado como `leadgen_id`
# real de Meta en la Fase 20 de la investigación de tesis IA -- ver
# docs/investigacion-tesis-ia/25_VERIFICACION_ADMINISTRATIVA_META_FASE20.md y
# 26_DISENO_ATRIBUCION_DETERMINISTICA_FASE21.md). Relación 1:1 con `revenue_leads`, en tabla
# separada a propósito (ver comentario de la migración) -- NUNCA sobrescribe
# `revenue_leads.adset_id`/`advert_id` (esos siguen siendo nombres de texto libre, ver Fase 17).
#
# `verification_status` reutiliza EXACTAMENTE el vocabulario ya validado en las pruebas reales
# de Fases 18 y 20 contra la Graph API -- no se inventa una taxonomía nueva para producción:
#   - pendiente: fila creada, todavía no se intentó resolver contra Meta.
#   - confirmada: id de Meta coincide, fecha consistente, los 4 identificadores presentes.
#   - parcialmente_verificable: id coincide pero falta algún identificador o la fecha no cuadra.
#   - no_correspondiente: el id devuelto por Meta NO coincide con el social_lead_id consultado.
#   - no_verificable_permisos_o_ausencia: error de Graph API ambiguo entre falta de permiso,
#     objeto de otro activo, o dato caducado (mismo criterio ya aplicado en Fase 18/20: un error
#     así NUNCA se reclasifica como no_correspondiente).
#   - no_verificable_otro_error: cualquier otro error no clasificable en los anteriores.
# == Schema Information
#
# Table name: revenue_lead_meta_attributions
#
#  id                   :bigint           not null, primary key
#  fetch_error_code     :integer
#  fetch_error_subcode  :integer
#  fetched_at           :datetime
#  meta_lead_created_at :datetime
#  source               :string           default("graph_api_leadgen_lookup"), not null
#  verification_status  :string           default("pendiente"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  meta_ad_account_id   :string
#  meta_ad_id           :string
#  meta_adset_id        :string
#  meta_campaign_id     :string
#  meta_form_id         :string
#  revenue_lead_id      :bigint           not null
#  social_lead_id       :string           not null
#
# Indexes
#
#  idx_on_account_id_verification_status_acf5f85a82          (account_id,verification_status)
#  index_revenue_lead_meta_attributions_on_meta_ad_id        (meta_ad_id)
#  index_revenue_lead_meta_attributions_on_meta_adset_id     (meta_adset_id)
#  index_revenue_lead_meta_attributions_on_meta_campaign_id  (meta_campaign_id)
#  index_revenue_lead_meta_attributions_on_revenue_lead_id   (revenue_lead_id) UNIQUE
#
class RevenueLeadMetaAttribution < ApplicationRecord
  VERIFICATION_STATUSES = %w[
    pendiente confirmada parcialmente_verificable no_correspondiente
    no_verificable_permisos_o_ausencia no_verificable_otro_error
  ].freeze

  # Estados que SÍ requieren haber intentado la llamada -- fetched_at es obligatorio para estos,
  # pero NO para "pendiente" (corrección explícita pedida en Fase 22 §2).
  FETCHED_STATUSES = (VERIFICATION_STATUSES - %w[pendiente]).freeze

  belongs_to :account
  belongs_to :revenue_lead

  validates :social_lead_id, presence: true
  validates :revenue_lead_id, uniqueness: true
  validates :verification_status, inclusion: { in: VERIFICATION_STATUSES }
  validates :fetched_at, presence: true, if: -> { FETCHED_STATUSES.include?(verification_status) }
  validate :account_matches_revenue_lead

  scope :confirmada, -> { where(verification_status: 'confirmada') }
  scope :pendiente, -> { where(verification_status: 'pendiente') }
  scope :no_verificable, -> { where(verification_status: VERIFICATION_STATUSES.grep(/\Ano_verificable/)) }

  def confirmada?
    verification_status == 'confirmada'
  end

  private

  # Aislamiento por cuenta (Fase 22 §2): revenue_lead_id es globalmente único entre cuentas (es
  # un bigint autoincremental compartido), pero nunca debe poder crearse una atribución cuyo
  # account_id no coincida con el account_id real del revenue_lead referenciado -- cruzaría datos
  # entre cuentas distintas si algún llamador pasa el account_id equivocado por error.
  def account_matches_revenue_lead
    return if revenue_lead.blank? || account_id.blank?
    return if revenue_lead.account_id == account_id

    errors.add(:account_id, 'debe coincidir con el account_id del revenue_lead asociado')
  end
end
