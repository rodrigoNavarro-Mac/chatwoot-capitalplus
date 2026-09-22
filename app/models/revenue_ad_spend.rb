# Inversión de Meta Ads: captura manual del equipo (source: manual, ver Fase 1 original del tab
# Marketing) O sincronizada automáticamente desde Meta Marketing API (source: meta_api, ver
# RevenueIntelligence::SyncMetaAdsSpendJob). Nunca vive en revenue_rollups (esa tabla se borra/
# reconstruye cada hora vía RefreshAggregatesJob) -- por eso esta tabla existe aparte.
#
# El match contra revenue_leads/revenue_deals es por NOMBRE (campaign_name/adset_name/
# advert_name), nunca por id: confirmado que Zoho/Meta nunca entrega un id real para esta cuenta
# (ver RevenueIntelligence::LeadMapper). adset_name/advert_name son opcionales a propósito — la
# captura manual puede ser solo a nivel campaña o campaña+adset (los registros meta_api siempre
# traen los tres, vienen de la Insights API a nivel anuncio).
#
# Precedencia cuando conviven ambas fuentes para la misma campaña: "automático manda" (decisión
# explícita del usuario) -- ver RevenueIntelligenceBuilder#spend_records_in_range.
# == Schema Information
#
# Table name: revenue_ad_spends
#
#  id            :bigint           not null, primary key
#  adset_name    :string
#  advert_name   :string
#  amount        :decimal(14, 2)   not null
#  campaign_name :string           not null
#  currency      :string           default("MXN"), not null
#  desarrollo    :string
#  period_end    :date             not null
#  period_start  :date             not null
#  source        :string           default("manual"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint
#  updated_by_id :bigint
#
# Indexes
#
#  idx_on_account_id_campaign_name_source_15eb13a608     (account_id,campaign_name,source)
#  idx_on_account_id_period_start_period_end_de56c7d911  (account_id,period_start,period_end)
#  idx_revenue_ad_spends_dedup                           (account_id,campaign_name,adset_name,advert_name,period_start,period_end) UNIQUE
#
class RevenueAdSpend < ApplicationRecord
  CURRENCIES = %w[MXN].freeze
  SOURCES = %w[manual meta_api].freeze

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true

  validates :campaign_name, presence: true
  validates :period_start, :period_end, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, inclusion: { in: CURRENCIES }
  validates :source, inclusion: { in: SOURCES }
  validates :campaign_name, uniqueness: { scope: [:account_id, :adset_name, :advert_name, :period_start, :period_end] }
  validate :period_start_before_period_end

  scope :meta_api, -> { where(source: 'meta_api') }
  scope :manual, -> { where(source: 'manual') }

  # Contenido, no solapado: mismo criterio que RevenueIntelligence::RevenueIntelligenceBuilder
  # para decidir si un registro de inversión aplica al rango de fechas filtrado en el dashboard.
  scope :within_period, ->(since, until_date) { where('period_start >= ? AND period_end <= ?', since, until_date) }

  def self.for_ad(campaign_name:, adset_name: nil, advert_name: nil)
    where(campaign_name: campaign_name, adset_name: adset_name, advert_name: advert_name)
  end

  # Solapamientos (no duplicados exactos, esos ya los bloquea la validación de unicidad) —
  # usado por el controlador para advertir sin bloquear, ver sección 10.6 del brief de producto.
  def overlapping
    self.class.where(account_id: account_id, campaign_name: campaign_name, adset_name: adset_name, advert_name: advert_name)
        .where.not(id: id)
        .where('period_start <= ? AND period_end >= ?', period_end, period_start)
  end

  private

  def period_start_before_period_end
    return if period_start.blank? || period_end.blank?
    return if period_start <= period_end

    errors.add(:period_end, 'debe ser posterior o igual a la fecha inicial')
  end
end
