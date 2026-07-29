require 'rails_helper'

RSpec.describe 'Conversation Merge Action API', type: :request do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  # se crea una conversación en otra cuenta antes para desalinear id (PK global) de display_id (contador por cuenta),
  # igual que ocurre en producción, y así el spec detecte si el controller busca por el id equivocado
  let!(:other_account_conversation) { create(:conversation) } # rubocop:disable RSpec/LetSetup
  let!(:base_conversation) { create(:conversation, account: account, contact: contact) }
  let!(:mergee_conversation) { create(:conversation, account: account, contact: contact) }

  describe 'POST /api/v1/accounts/{account.id}/actions/conversation_merge' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/actions/conversation_merge"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:merge_action) { double }

      before do
        allow(ConversationMergeAction).to receive(:new).and_return(merge_action)
        allow(merge_action).to receive(:perform).and_return(base_conversation)
      end

      it 'merges two conversations by calling conversation merge action' do
        expect(base_conversation.id).not_to eq(base_conversation.display_id)

        post "/api/v1/accounts/#{account.id}/actions/conversation_merge",
             params: { base_conversation_id: base_conversation.display_id, mergee_conversation_id: mergee_conversation.display_id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['id']).to eq(base_conversation.display_id)
        expected_params = { account: account, base_conversation: base_conversation, mergee_conversation: mergee_conversation }
        expect(ConversationMergeAction).to have_received(:new).with(expected_params)
        expect(merge_action).to have_received(:perform)
      end
    end
  end
end
