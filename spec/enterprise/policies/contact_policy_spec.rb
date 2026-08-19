# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enterprise::ContactPolicy', type: :policy do
  subject(:contact_policy) { ContactPolicy }

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:custom_role) { create(:custom_role, account: account, permissions: ['contact_manage']) }
  let(:agent) { create(:user) }
  let(:account_user) { create(:account_user, user: agent, account: account, role: :agent, custom_role: custom_role) }
  let(:agent_context) { { user: agent, account: account, account_user: account_user } }

  let(:view_role) { create(:custom_role, account: account, permissions: ['contact_view']) }
  let(:agent_with_view) { create(:user) }
  let(:agent_with_view_account_user) do
    create(:account_user, user: agent_with_view, account: account, role: :agent, custom_role: view_role)
  end
  let(:agent_with_view_context) { { user: agent_with_view, account: account, account_user: agent_with_view_account_user } }

  let(:no_access_role) { create(:custom_role, account: account, permissions: ['report_manage']) }
  let(:agent_with_no_access) { create(:user) }
  let(:agent_with_no_access_account_user) do
    create(:account_user, user: agent_with_no_access, account: account, role: :agent, custom_role: no_access_role)
  end
  let(:agent_with_no_access_context) do
    { user: agent_with_no_access, account: account, account_user: agent_with_no_access_account_user }
  end

  permissions :export? do
    context 'when agent has contact_manage permission' do
      it { expect(contact_policy).to permit(agent_context, contact) }
    end
  end

  permissions :import? do
    context 'when agent has contact_manage permission' do
      it { expect(contact_policy).to permit(agent_context, contact) }
    end
  end

  permissions :show? do
    context 'when agent has contact_view permission' do
      it { expect(contact_policy).to permit(agent_with_view_context, contact) }
    end

    context 'when agent has contact_manage permission' do
      it { expect(contact_policy).to permit(agent_context, contact) }
    end

    context 'when custom role has no contact permission at all' do
      it { expect(contact_policy).not_to permit(agent_with_no_access_context, contact) }
    end
  end

  permissions :create?, :update? do
    context 'when agent only has contact_view permission' do
      it { expect(contact_policy).not_to permit(agent_with_view_context, contact) }
    end

    context 'when agent has contact_manage permission' do
      it { expect(contact_policy).to permit(agent_context, contact) }
    end
  end
end
