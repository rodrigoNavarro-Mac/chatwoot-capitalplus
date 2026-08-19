require 'rails_helper'

RSpec.describe RecordSharePolicy, type: :policy do
  subject(:record_share_policy) { described_class }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:administrator_context) do
    { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) }
  end

  let(:agent) { create(:user, account: account) }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }

  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:record_share) { conversation.record_shares.build(shared_with: agent, shared_by: administrator) }

  permissions :create? do
    context 'when administrator' do
      it { expect(record_share_policy).to permit(administrator_context, record_share) }
    end

    context 'when agent has no access to the underlying conversation' do
      it { expect(record_share_policy).not_to permit(agent_context, record_share) }
    end

    context 'when agent has inbox access to the underlying conversation' do
      before { create(:inbox_member, user: agent, inbox: inbox) }

      it { expect(record_share_policy).to permit(agent_context, record_share) }
    end
  end
end
