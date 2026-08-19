# == Schema Information
#
# Table name: record_shares
#
#  id               :bigint           not null, primary key
#  access_level     :integer          default("view"), not null
#  shareable_type   :string           not null
#  shared_with_type :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  shareable_id     :bigint           not null
#  shared_by_id     :bigint           not null
#  shared_with_id   :bigint           not null
#
# Indexes
#
#  idx_unique_record_share                                     (shareable_type,shareable_id,shared_with_type,shared_with_id) UNIQUE
#  index_record_shares_on_account_id                           (account_id)
#  index_record_shares_on_shareable_type_and_shareable_id      (shareable_type,shareable_id)
#  index_record_shares_on_shared_with_type_and_shared_with_id  (shared_with_type,shared_with_id)
#
class RecordShare < ApplicationRecord
  SHAREABLE_TYPES = %w[Conversation Contact].freeze
  SHARED_WITH_TYPES = %w[User Team].freeze

  belongs_to :account
  belongs_to :shareable, polymorphic: true
  belongs_to :shared_with, polymorphic: true
  belongs_to :shared_by, class_name: 'User'

  enum access_level: { view: 0, manage: 1 }

  validates :shareable_type, inclusion: { in: SHAREABLE_TYPES }
  validates :shared_with_type, inclusion: { in: SHARED_WITH_TYPES }
  validates :shared_with_id, uniqueness: { scope: %i[shareable_type shareable_id shared_with_type] }
end
