# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enterprise::CadenceCallTaskPolicy', type: :policy do
  subject(:policy) { CadenceCallTaskPolicy }

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
    # index? is intentionally true for any authenticated agent (even without a custom role) —
    # the actual "own vs team vs everyone" restriction happens in the controller's scope
    # (CadenceCallTask.own_or_team), not at the Pundit gate.
    context 'when plain agent without a custom role' do
      it { expect(policy).to permit(agent_context, CadenceCallTask) }
    end

    context 'when agent has cadence_view permission' do
      it { expect(policy).to permit(agent_with_view_context, CadenceCallTask) }
    end
  end

  permissions :complete? do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:cadence_definition) { create(:cadence_definition, account: account, inbox: inbox) }
    let(:enrollment) do
      create(:cadence_enrollment, account: account, conversation: conversation, inbox: inbox, cadence_definition: cadence_definition)
    end
    let(:task) { create(:cadence_call_task, account: account, cadence_enrollment: enrollment, conversation: conversation, user: agent) }

    context 'when task belongs to the agent' do
      it { expect(policy).to permit(agent_context, task) }
    end

    context 'when task belongs to someone else and agent only has cadence_view' do
      let(:other_task) do
        create(:cadence_call_task, account: account, cadence_enrollment: enrollment, conversation: conversation, user: agent, step: 2)
      end

      it { expect(policy).not_to permit(agent_with_view_context, other_task) }
    end

    context 'when agent has cadence_manage permission' do
      it { expect(policy).to permit(agent_with_manage_context, task) }
    end
  end
end
