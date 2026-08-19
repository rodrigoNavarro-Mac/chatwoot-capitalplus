# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enterprise::CadenceStepDefinitionPolicy', type: :policy do
  subject(:policy) { CadenceStepDefinitionPolicy }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }

  let(:view_role) { create(:custom_role, account: account, permissions: ['cadence_view']) }
  let(:agent_with_view) { create(:user) }
  let(:agent_with_view_account_user) do
    create(:account_user, user: agent_with_view, account: account, role: :agent, custom_role: view_role)
  end
  let(:agent_with_view_context) { { user: agent_with_view, account: account, account_user: agent_with_view_account_user } }

  let(:manage_role) { create(:custom_role, account: account, permissions: ['cadence_manage']) }
  let(:agent_with_manage) { create(:user) }
  let(:agent_with_manage_account_user) do
    create(:account_user, user: agent_with_manage, account: account, role: :agent, custom_role: manage_role)
  end
  let(:agent_with_manage_context) do
    { user: agent_with_manage, account: account, account_user: agent_with_manage_account_user }
  end

  permissions :index? do
    context 'when plain agent without a custom role' do
      it { expect(policy).not_to permit(agent_context, CadenceStepDefinition) }
    end

    context 'when agent has cadence_view permission' do
      it { expect(policy).to permit(agent_with_view_context, CadenceStepDefinition) }
    end
  end

  permissions :create?, :update?, :destroy?, :reorder? do
    context 'when agent only has cadence_view permission' do
      it { expect(policy).not_to permit(agent_with_view_context, CadenceStepDefinition) }
    end

    context 'when agent has cadence_manage permission' do
      it { expect(policy).to permit(agent_with_manage_context, CadenceStepDefinition) }
    end
  end
end
