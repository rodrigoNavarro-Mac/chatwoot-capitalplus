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
#  send_retry_count          :integer          default(0), not null
#  status                    :string           default("active"), not null
#  steps_snapshot            :jsonb            not null
#  stopped_reason            :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
#  assignee_id               :bigint
#  cadence_definition_id     :bigint           not null
#  contact_id                :bigint
#  conversation_id           :bigint           not null
#  inbox_id                  :bigint           not null
#
# Indexes
#
#  index_cadence_enrollments_on_account_id_and_status  (account_id,status)
#  index_cadence_enrollments_on_assignee_id            (assignee_id)
#  index_cadence_enrollments_on_cadence_definition_id  (cadence_definition_id)
#  index_cadence_enrollments_on_contact_id             (contact_id)
#  index_cadence_enrollments_on_conversation_id        (conversation_id) UNIQUE
#  index_cadence_enrollments_on_next_action_at         (next_action_at)
#
class CadenceEnrollment < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :contact, optional: true
  belongs_to :inbox
  belongs_to :cadence_definition
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
  scope :filter_by_cadence_definition_id, ->(id) { where(cadence_definition_id: id) if id.present? }
  scope :filter_by_assignee_id, ->(assignee_id) { where(assignee_id: assignee_id) if assignee_id.present? }
  scope :filter_by_team_id, lambda { |team_id|
    joins(:conversation).where(conversations: { team_id: team_id }) if team_id.present?
  }
  scope :filter_by_status, ->(status) { where(status: status) if status.present? }
  scope :filter_by_step, ->(step) { where(current_step: step) if step.present? }
  scope :own_or_team, lambda { |user|
    team_conversation_ids = Conversation.where(team_id: user.teams.select(:id)).select(:id)
    where(assignee_id: user.id).or(where(conversation_id: team_conversation_ids))
  }

  def responded_since_last_template?
    last_lead_response_at.present? && last_template_sent_at.present? && last_lead_response_at > last_template_sent_at
  end

  # steps_snapshot congela la configuración de CadenceStepDefinition vigente al momento del
  # enroll!; los servicios del motor de cadencia nunca vuelven a leer la tabla viva, así que
  # editar/reordenar/borrar pasos en el UI no afecta a leads ya inscritos.
  def steps_snapshot
    super.map(&:with_indifferent_access)
  end

  def step_definition_for(position)
    steps_snapshot.find { |definition| definition[:position] == position }
  end

  def total_steps
    steps_snapshot.size
  end
end
