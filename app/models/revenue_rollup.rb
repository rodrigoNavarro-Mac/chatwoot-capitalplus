# Agregado dimensional genérico — ver RevenueIntelligence::RefreshAggregatesJob y el plan de
# Fase 3 para la convención de dimension_type/dimension_id/metric. Nunca se escribe con .save/
# .create directo en operación normal: RefreshAggregatesJob usa upsert_all para acumular
# count/sum_value de forma atómica (ver ReportingEventsRollup, mismo patrón).
# == Schema Information
#
# Table name: revenue_rollups
#
#  id             :bigint           not null, primary key
#  count          :integer          default(0), not null
#  date           :date             not null
#  dimension_type :string           not null
#  metric         :string           not null
#  sum_value      :decimal(14, 2)   default(0.0), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  dimension_id   :string           not null
#
# Indexes
#
#  idx_on_account_id_dimension_type_date_5f0e1de5f3  (account_id,dimension_type,date)
#  idx_revenue_rollups_dedup                         (account_id,date,dimension_type,dimension_id,metric) UNIQUE
#
class RevenueRollup < ApplicationRecord
  DIMENSION_TYPES = %w[funnel agent campaign adset advert pipeline_stage call_conversion objection_conversion].freeze

  belongs_to :account

  validates :dimension_type, presence: true, inclusion: { in: DIMENSION_TYPES }
  validates :dimension_id, :metric, :date, presence: true
end
