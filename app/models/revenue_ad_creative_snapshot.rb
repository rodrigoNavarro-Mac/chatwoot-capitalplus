# Snapshot versionado de metadatos de creativo -- ver Fase 22 (docs/investigacion-tesis-ia/
# 27_IMPLEMENTACION_ATRIBUCION_FASE22.md) y el comentario de la migración
# `20261020190400_create_revenue_ad_creative_snapshots.rb`. Append-only: un mismo meta_ad_id
# puede tener varias filas a lo largo del tiempo (el anunciante edita el creativo sin cambiar de
# ad_id) -- "la versión vigente" se resuelve en consulta (más reciente sin pasarse de una fecha
# dada), nunca sobrescribiendo una fila existente.
#
# Solo guarda los campos de la lista permitida (Fase 22 §3) -- deliberadamente NO tiene una
# columna de respuesta cruda tipo jsonb.
# == Schema Information
#
# Table name: revenue_ad_creative_snapshots
#
#  id                  :bigint           not null, primary key
#  body                :text
#  call_to_action_type :string
#  fetched_at          :datetime         not null
#  format              :string
#  media_type          :string
#  title               :text
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  creative_id         :string
#  meta_ad_id          :string           not null
#  meta_adset_id       :string
#  meta_campaign_id    :string
#
# Indexes
#
#  idx_on_meta_ad_id_fetched_at_2de14f774d  (meta_ad_id,fetched_at)
#
class RevenueAdCreativeSnapshot < ApplicationRecord
  ALLOWED_FORMATS = %w[image video carousel other].freeze

  belongs_to :account

  validates :meta_ad_id, presence: true
  validates :fetched_at, presence: true
  validates :format, inclusion: { in: ALLOWED_FORMATS }, allow_nil: true

  scope :for_ad, ->(meta_ad_id) { where(meta_ad_id: meta_ad_id) }

  # Versión vigente para una fecha dada (point-in-time, mismo principio que el resto del
  # dataset de A/C desde Fase 9) -- la más reciente capturada SIN pasarse de esa fecha. Devuelve
  # nil si no hay ningún snapshot anterior o igual a esa fecha (nunca se usa una versión futura
  # respecto al punto de referencia solicitado).
  def self.as_of(meta_ad_id, at)
    for_ad(meta_ad_id).where('fetched_at <= ?', at).order(fetched_at: :desc).first
  end
end
