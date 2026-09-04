# Bookkeeping de "hasta qué Modified_Time ya sincronicé" por cuenta y tipo de sync. Ver
# RevenueIntelligence::SyncCursorService — el cursor solo avanza si el job correspondiente
# terminó sin excepción, así que una corrida fallida a medias no pierde el hueco sin sincronizar.
#
# == Schema Information
#
# Table name: revenue_sync_cursors
#
#  id              :bigint           not null, primary key
#  last_error      :text
#  last_run_status :string
#  last_synced_at  :datetime
#  sync_type       :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#
# Indexes
#
#  index_revenue_sync_cursors_on_account_id_and_sync_type  (account_id,sync_type) UNIQUE
#
class RevenueSyncCursor < ApplicationRecord
  SYNC_TYPES = %w[leads deals stage_history meetings events journeys call_features rollups].freeze

  belongs_to :account

  validates :sync_type, presence: true, inclusion: { in: SYNC_TYPES }, uniqueness: { scope: :account_id }
end
