# == Schema Information
#
# Table name: cadence_call_tasks
#
#  id                    :bigint           not null, primary key
#  completed_at          :datetime
#  notified_at           :datetime
#  status                :string           default("pending"), not null
#  step                  :integer          not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  cadence_enrollment_id :bigint           not null
#  completed_by_id       :bigint
#  conversation_id       :bigint           not null
#  user_id               :bigint
#
# Indexes
#
#  idx_cadence_call_tasks_on_enrollment_and_step      (cadence_enrollment_id,step) UNIQUE
#  index_cadence_call_tasks_on_account_id_and_status  (account_id,status)
#  index_cadence_call_tasks_on_user_id                (user_id)
#
class CadenceCallTask < ApplicationRecord
  belongs_to :account
  belongs_to :cadence_enrollment
  belongs_to :conversation
  belongs_to :user, optional: true
  belongs_to :completed_by, class_name: 'User', optional: true

  enum status: { pending: 'pending', completed: 'completed', skipped: 'skipped' }

  validates :step, presence: true
  validates :cadence_enrollment_id, uniqueness: { scope: :step }

  scope :filter_by_date_range, ->(range) { where(created_at: range) if range.present? }
  scope :filter_by_user_id, ->(user_id) { where(user_id: user_id) if user_id.present? }
  scope :filter_by_status, ->(status) { where(status: status) if status.present? }

  def complete!(by_user)
    update!(status: :completed, completed_at: Time.current, completed_by: by_user)
  end
end
