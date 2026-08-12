# == Schema Information
#
# Table name: weekly_ops_reports
#
#  id              :bigint           not null, primary key
#  kpis            :jsonb            not null
#  llm_analysis    :text
#  period_end      :date             not null
#  period_start    :date             not null
#  period_type     :string           default("week"), not null
#  status          :string           default("pending"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  generated_by_id :bigint
#  inbox_id        :bigint           not null
#
# Indexes
#
#  index_weekly_ops_reports_on_account_id               (account_id)
#  index_weekly_ops_reports_on_generated_by_id          (generated_by_id)
#  index_weekly_ops_reports_on_inbox_period_start_type  (inbox_id,period_start,period_type) UNIQUE
#
# Snapshot persistido de un reporte semanal operativo (KPIs + análisis del LLM) para un inbox y
# periodo dados. Se genera automáticamente cada semana (Reports::GenerateWeeklyOpsReportJob) o
# on-demand desde el dashboard; una vez generado no se recalcula al volver a abrirlo.
class WeeklyOpsReport < ApplicationRecord
  belongs_to :account
  belongs_to :inbox
  belongs_to :generated_by, class_name: 'User', optional: true

  enum status: { pending: 'pending', completed: 'completed', failed: 'failed' }
  enum period_type: { week: 'week', month: 'month', quarter: 'quarter' }

  validates :period_start, presence: true
  validates :period_end, presence: true
  validates :period_start, uniqueness: { scope: [:inbox_id, :period_type] }

  scope :filter_by_inbox_id, ->(inbox_id) { where(inbox_id: inbox_id) if inbox_id.present? }
  scope :recent_first, -> { order(period_start: :desc) }
end
