# == Schema Information
#
# Table name: cadence_enrollments
#
#  id                        :bigint           not null, primary key
#  cadence_name              :string           default("cadencia_comercial_default"), not null
#  current_step              :integer          default(0), not null
#  last_call_task_created_at :datetime
#  last_lead_response_at     :datetime
#  last_template_sent_at     :datetime
#  next_action_at            :datetime
#  status                    :string           default("active"), not null
#  stopped_reason            :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
#  assignee_id               :bigint
#  contact_id                :bigint
#  conversation_id           :bigint           not null
#  inbox_id                  :bigint           not null
#
# Indexes
#
#  index_cadence_enrollments_on_account_id_and_status  (account_id,status)
#  index_cadence_enrollments_on_assignee_id            (assignee_id)
#  index_cadence_enrollments_on_contact_id             (contact_id)
#  index_cadence_enrollments_on_conversation_id        (conversation_id) UNIQUE
#  index_cadence_enrollments_on_next_action_at         (next_action_at)
#
class CadenceEnrollment < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :contact, optional: true
  belongs_to :inbox
  belongs_to :assignee, class_name: 'User', optional: true

  has_many :cadence_events, dependent: :destroy
  has_many :cadence_call_tasks, dependent: :destroy

  enum status: {
    active: 'active',
    waiting_response: 'waiting_response',
    pending_agent_call: 'pending_agent_call',
    paused_by_response: 'paused_by_response',
    completed: 'completed',
    failed: 'failed',
    recovered: 'recovered',
    cold: 'cold'
  }

  validates :conversation_id, uniqueness: true

  ACTIVE_STATUSES = %w[active waiting_response pending_agent_call].freeze

  scope :in_progress, -> { where(status: ACTIVE_STATUSES) }
  scope :filter_by_date_range, ->(range) { where(created_at: range) if range.present? }
  scope :filter_by_inbox_id, ->(inbox_id) { where(inbox_id: inbox_id) if inbox_id.present? }
  scope :filter_by_assignee_id, ->(assignee_id) { where(assignee_id: assignee_id) if assignee_id.present? }
  scope :filter_by_team_id, lambda { |team_id|
    joins(:conversation).where(conversations: { team_id: team_id }) if team_id.present?
  }
  scope :filter_by_status, ->(status) { where(status: status) if status.present? }
  scope :filter_by_step, ->(step) { where(current_step: step) if step.present? }

  def responded_since_last_template?
    last_lead_response_at.present? && last_template_sent_at.present? && last_lead_response_at > last_template_sent_at
  end
end
