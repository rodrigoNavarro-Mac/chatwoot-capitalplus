# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enterprise::CadenceEnrollmentPolicy', type: :policy do
  subject(:policy) { CadenceEnrollmentPolicy }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:cadence_definition) { create(:cadence_definition, account: account, inbox: inbox) }

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

  permissions :index?, :create?, :eligible_conversations?, :enroll_past_leads?, :retry_failed?, :pause?, :resume?, :cancel? do
    context 'when plain agent without a custom role' do
      it { expect(policy).not_to permit(agent_context, CadenceEnrollment) }
    end

    context 'when agent has cadence_manage permission' do
      it { expect(policy).to permit(agent_with_manage_context, CadenceEnrollment) }
    end
  end

  permissions :index? do
    context 'when agent only has cadence_view permission' do
      it { expect(policy).to permit(agent_with_view_context, CadenceEnrollment) }
    end
  end

  permissions :show? do
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:enrollment) do
      create(:cadence_enrollment, account: account, conversation: conversation, inbox: inbox,
                                  cadence_definition: cadence_definition, assignee: agent_with_view)
    end

    context 'when the enrollment is assigned to the agent with cadence_view' do
      it { expect(policy).to permit(agent_with_view_context, enrollment) }
    end

    context 'when the enrollment belongs to someone else and agent only has cadence_view' do
      let(:other_enrollment) do
        create(:cadence_enrollment, account: account,
                                    conversation: create(:conversation, account: account, inbox: inbox),
                                    inbox: inbox, cadence_definition: cadence_definition)
      end

      it { expect(policy).not_to permit(agent_with_view_context, other_enrollment) }
    end

    context 'when agent has cadence_manage permission' do
      it { expect(policy).to permit(agent_with_manage_context, enrollment) }
    end
  end
end
