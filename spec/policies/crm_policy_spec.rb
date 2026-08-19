# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CrmPolicy, type: :policy do
  subject(:crm_policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }

  permissions :view?, :manage? do
    context 'when administrator' do
      it { expect(crm_policy).to permit(administrator_context, :crm) }
    end

    context 'when agent without a custom role' do
      it { expect(crm_policy).to permit(agent_context, :crm) }
    end
  end
end
