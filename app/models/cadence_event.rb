# == Schema Information
#
# Table name: cadence_events
#
#  id                    :bigint           not null, primary key
#  actor_type            :string
#  event_type            :string           not null
#  metadata              :jsonb
#  occurred_at           :datetime         not null
#  step                  :integer
#  template_key          :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  actor_id              :bigint
#  cadence_enrollment_id :bigint           not null
#  contact_id            :bigint
#  conversation_id       :bigint           not null
#
# Indexes
#
#  idx_on_account_id_event_type_occurred_at_41b1937298  (account_id,event_type,occurred_at)
#  index_cadence_events_on_cadence_enrollment_id        (cadence_enrollment_id)
#  index_cadence_events_on_conversation_id              (conversation_id)
#
class CadenceEvent < ApplicationRecord
  belongs_to :account
  belongs_to :cadence_enrollment
  belongs_to :conversation
  belongs_to :contact, optional: true

  EVENT_TYPES = %w[
    cadence_started
    template_sent
    lead_replied
    call_task_created
    call_completed
    cadence_paused
    cadence_resumed
    cadence_completed
    cadence_recovered
    cadence_marked_cold
    cadence_failed
  ].freeze

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :occurred_at, presence: true

  before_validation :set_occurred_at, on: :create

  scope :filter_by_date_range, ->(range) { where(occurred_at: range) if range.present? }
  scope :filter_by_event_type, ->(event_type) { where(event_type: event_type) if event_type.present? }
  scope :filter_by_step, ->(step) { where(step: step) if step.present? }
  scope :filter_by_template_key, ->(template_key) { where(template_key: template_key) if template_key.present? }

  private

  def set_occurred_at
    self.occurred_at ||= Time.current
  end
end
