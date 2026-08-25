# == Schema Information
#
# Table name: custom_roles
#
#  id          :bigint           not null, primary key
#  description :string
#  name        :string
#  permissions :text             default([]), is an Array
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_custom_roles_on_account_id  (account_id)
#

# Available permissions for custom roles:
# - 'conversation_manage': Can manage all conversations.
# - 'conversation_unassigned_manage': Can manage unassigned conversations and assign to self.
# - 'conversation_participating_manage': Can manage conversations they are participating in (assigned to or a participant).
# - 'contact_view' / 'contact_manage': Read-only vs full access to contacts.
# - 'report_view' / 'report_manage': Read-only vs full access (export/download) to reports.
# - 'knowledge_base_view' / 'knowledge_base_manage': Read-only vs full access to the knowledge base.
# - 'cadence_view' / 'cadence_manage': Read-only vs full access to cadences (definitions, enrollments, call tasks, analytics).
# - 'sales_funnel_view' / 'sales_funnel_manage': Read-only vs full access to sales funnel goals.
# - 'weekly_ops_report_view' / 'weekly_ops_report_manage': Read-only vs full access to the weekly ops report.
# - 'campaign_view' / 'campaign_manage': Read-only vs full access to campaigns.
# - 'crm_view' / 'crm_manage': Read-only vs full access to the CRM integration panel (push/create/sync).
#
# For most modules 'manage' implies 'view' (enforced client-side when building the role).

class CustomRole < ApplicationRecord
  belongs_to :account
  has_many :account_users, dependent: :nullify

  before_destroy :capture_filtered_unread_count_user_ids, prepend: true
  after_update_commit :invalidate_filtered_unread_count_visibility_update, if: :filtered_unread_count_permissions_changed?
  after_destroy_commit :invalidate_filtered_unread_count_visibility_destroy

  PERMISSIONS = %w[
    conversation_manage
    conversation_unassigned_manage
    conversation_participating_manage
    contact_view
    contact_manage
    report_view
    report_manage
    knowledge_base_view
    knowledge_base_manage
    cadence_view
    cadence_manage
    sales_funnel_view
    sales_funnel_manage
    weekly_ops_report_view
    weekly_ops_report_manage
    campaign_view
    campaign_manage
    crm_view
    crm_manage
  ].freeze

  validates :name, presence: true
  validates :permissions, inclusion: { in: PERMISSIONS }

  private

  def filtered_unread_count_permissions_changed?
    previous_changes.key?('permissions')
  end

  def capture_filtered_unread_count_user_ids
    @filtered_unread_count_user_ids = account_users.pluck(:user_id)
  end

  def invalidate_filtered_unread_count_visibility_update
    invalidate_filtered_unread_count_visibility(account_users.pluck(:user_id))
  end

  def invalidate_filtered_unread_count_visibility_destroy
    invalidate_filtered_unread_count_visibility(@filtered_unread_count_user_ids)
  end

  def invalidate_filtered_unread_count_visibility(user_ids)
    invalidator = ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account)
    visibility_changed = invalidator.users_visibility_changed!(user_ids: user_ids)

    dispatch_account_cache_invalidated if visibility_changed
  end

  def dispatch_account_cache_invalidated
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CACHE_INVALIDATED, Time.zone.now, account: account, cache_keys: account.cache_keys)
  end
end
