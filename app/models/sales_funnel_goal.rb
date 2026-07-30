# == Schema Information
#
# Table name: sales_funnel_goals
#
#  id               :bigint           not null, primary key
#  development_key  :string           not null
#  period_month     :date             not null
#  stage            :string           not null
#  target_percent   :decimal(5, 2)    default(0.0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#
# Indexes
#
#  index_sales_funnel_goals_on_account_development_stage_period  (account_id,development_key,stage,period_month) UNIQUE
#  index_sales_funnel_goals_on_account_id                        (account_id)
#
class SalesFunnelGoal < ApplicationRecord
  # Etapas del embudo que arma V2::Reports::SalesFunnelBuilder — ver ese builder para el
  # significado exacto de cada una (leads totales, contestados por cliente, con deal, cerrado
  # ganado).
  STAGES = %w[leads customer_replied has_deal closed_won].freeze

  belongs_to :account

  before_validation :normalize_period_month

  validates :development_key, presence: true
  validates :stage, presence: true, inclusion: { in: STAGES }
  validates :period_month, presence: true
  validates :target_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :stage, uniqueness: { scope: [:account_id, :development_key, :period_month] }

  private

  def normalize_period_month
    self.period_month = period_month.beginning_of_month if period_month.present?
  end
end
