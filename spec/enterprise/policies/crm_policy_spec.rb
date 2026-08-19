# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enterprise::CrmPolicy', type: :policy do
  subject(:policy) { CrmPolicy }

  let(:account) { create(:account) }

  let(:view_role) { create(:custom_role, account: account, permissions: ['crm_view']) }
  let(:agent_with_view) { create(:user) }
  let(:agent_with_view_account_user) do
    create(:account_user, user: agent_with_view, account: account, role: :agent, custom_role: view_role)
  end
  let(:agent_with_view_context) { { user: agent_with_view, account: account, account_user: agent_with_view_account_user } }

  let(:manage_role) { create(:custom_role, account: account, permissions: ['crm_manage']) }
  let(:agent_with_manage) { create(:user) }
  let(:agent_with_manage_account_user) do
    create(:account_user, user: agent_with_manage, account: account, role: :agent, custom_role: manage_role)
  end
  let(:agent_with_manage_context) do
    { user: agent_with_manage, account: account, account_user: agent_with_manage_account_user }
  end

  let(:no_access_role) { create(:custom_role, account: account, permissions: ['report_manage']) }
  let(:agent_with_no_access) { create(:user) }
  let(:agent_with_no_access_account_user) do
    create(:account_user, user: agent_with_no_access, account: account, role: :agent, custom_role: no_access_role)
  end
  let(:agent_with_no_access_context) do
    { user: agent_with_no_access, account: account, account_user: agent_with_no_access_account_user }
  end

  permissions :view? do
    context 'when agent has crm_view permission' do
      it { expect(policy).to permit(agent_with_view_context, :crm) }
    end

    context 'when agent has crm_manage permission' do
      it { expect(policy).to permit(agent_with_manage_context, :crm) }
    end

    context 'when custom role has no crm permission at all' do
      it { expect(policy).not_to permit(agent_with_no_access_context, :crm) }
    end
  end

  permissions :manage? do
    context 'when agent only has crm_view permission' do
      it { expect(policy).not_to permit(agent_with_view_context, :crm) }
    end

    context 'when agent has crm_manage permission' do
      it { expect(policy).to permit(agent_with_manage_context, :crm) }
    end
  end
end
