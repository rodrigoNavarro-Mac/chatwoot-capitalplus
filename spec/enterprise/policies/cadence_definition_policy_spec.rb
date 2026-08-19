# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enterprise::CadenceDefinitionPolicy', type: :policy do
  subject(:cadence_definition_policy) { CadenceDefinitionPolicy }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:administrator_context) do
    { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) }
  end

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

  permissions :index?, :create?, :update?, :destroy? do
    context 'when administrator' do
      it { expect(cadence_definition_policy).to permit(administrator_context, CadenceDefinition) }
    end

    context 'when plain agent without a custom role' do
      it { expect(cadence_definition_policy).not_to permit(agent_context, CadenceDefinition) }
    end

    context 'when agent has cadence_manage permission' do
      it { expect(cadence_definition_policy).to permit(agent_with_manage_context, CadenceDefinition) }
    end
  end

  permissions :index? do
    context 'when agent only has cadence_view permission' do
      it { expect(cadence_definition_policy).to permit(agent_with_view_context, CadenceDefinition) }
    end
  end

  permissions :create?, :update?, :destroy? do
    context 'when agent only has cadence_view permission' do
      it { expect(cadence_definition_policy).not_to permit(agent_with_view_context, CadenceDefinition) }
    end
  end
end
