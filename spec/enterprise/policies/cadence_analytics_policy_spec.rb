# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enterprise::CadenceAnalyticsPolicy', type: :policy do
  subject(:policy) { CadenceAnalyticsPolicy }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }

  let(:view_role) { create(:custom_role, account: account, permissions: ['cadence_view']) }
  let(:agent_with_view) { create(:user) }
  let(:agent_with_view_account_user) do
    create(:account_user, user: agent_with_view, account: account, role: :agent, custom_role: view_role)
  end
  let(:agent_with_view_context) { { user: agent_with_view, account: account, account_user: agent_with_view_account_user } }

  permissions :summary?, :steps?, :agents?, :templates?, :variants? do
    context 'when plain agent without a custom role' do
      it { expect(policy).not_to permit(agent_context, :cadence_analytics) }
    end

    context 'when agent has cadence_view permission' do
      it { expect(policy).to permit(agent_with_view_context, :cadence_analytics) }
    end
  end
end
