# Una fila por cambio de etapa de un RevenueDeal, espejo del related list Stage_History de Zoho.
# Ver RevenueIntelligence::StageHistoryBuilder para cómo se calculan previous_stage/exited_at/
# duration_seconds.
#
# == Schema Information
#
# Table name: revenue_stage_events
#
#  id                 :bigint           not null, primary key
#  duration_seconds   :integer
#  entered_at         :datetime         not null
#  exited_at          :datetime
#  previous_stage     :string
#  raw_payload        :jsonb
#  source_system      :string           default("zoho_stage_history"), not null
#  stage              :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  revenue_contact_id :bigint
#  revenue_deal_id    :bigint
#  zoho_deal_id       :string           not null
#  zoho_history_id    :string
#
# Indexes
#
#  idx_on_account_id_revenue_contact_id_1059575ca7               (account_id,revenue_contact_id)
#  idx_stage_events_on_composite_key                             (account_id,zoho_deal_id,stage,entered_at) UNIQUE WHERE (zoho_history_id IS NULL)
#  idx_stage_events_on_history_id                                (account_id,zoho_deal_id,zoho_history_id) UNIQUE WHERE (zoho_history_id IS NOT NULL)
#  index_revenue_stage_events_on_account_id_and_revenue_deal_id  (account_id,revenue_deal_id)
#
class RevenueStageEvent < ApplicationRecord
  belongs_to :account
  belongs_to :revenue_deal, optional: true
  belongs_to :revenue_contact, optional: true

  validates :zoho_deal_id, :stage, :entered_at, presence: true
end
