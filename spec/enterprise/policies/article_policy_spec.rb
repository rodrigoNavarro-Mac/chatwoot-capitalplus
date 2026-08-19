# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enterprise::ArticlePolicy', type: :policy do
  subject(:article_policy) { ArticlePolicy }

  let(:account) { create(:account) }
  let(:view_role) { create(:custom_role, account: account, permissions: ['knowledge_base_view']) }
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
  let(:agent) { create(:user, account: account) } # Needed for author
  let(:portal) { create(:portal, account: account) }
  let(:article) { create(:article, account: account, portal: portal, author: agent) }

  # Create a custom role with knowledge_base_manage permission
  let(:custom_role) { create(:custom_role, account: account, permissions: ['knowledge_base_manage']) }
  let(:agent_with_role) { create(:user) } # Create without account
  let(:agent_with_role_account_user) do
    create(:account_user, user: agent_with_role, account: account, role: :agent, custom_role: custom_role)
  end
  let(:agent_with_role_context) do
    { user: agent_with_role, account: account, account_user: agent_with_role_account_user }
  end

  permissions :index?, :update?, :show?, :edit?, :create?, :destroy?, :reorder? do
    context 'when agent with knowledge_base_manage permission' do
      it { expect(article_policy).to permit(agent_with_role_context, article) }
    end
  end

  permissions :index?, :show? do
    context 'when agent with knowledge_base_view permission' do
      it { expect(article_policy).to permit(agent_with_view_context, article) }
    end

    context 'when custom role has no knowledge base permission at all' do
      it { expect(article_policy).not_to permit(agent_with_no_access_context, article) }
    end
  end

  permissions :update?, :create?, :destroy?, :reorder? do
    context 'when agent only has knowledge_base_view permission' do
      it { expect(article_policy).not_to permit(agent_with_view_context, article) }
    end
  end
end
