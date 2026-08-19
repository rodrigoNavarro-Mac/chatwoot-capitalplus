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
end
