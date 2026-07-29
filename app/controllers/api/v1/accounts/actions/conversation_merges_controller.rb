class Api::V1::Accounts::Actions::ConversationMergesController < Api::V1::Accounts::BaseController
  before_action :set_base_conversation
  before_action :set_mergee_conversation

  def create
    conversation_merge_action = ConversationMergeAction.new(
      account: Current.account,
      base_conversation: @base_conversation,
      mergee_conversation: @mergee_conversation
    )
    @base_conversation = conversation_merge_action.perform
  end

  private

  def set_base_conversation
    @base_conversation = conversations.find_by!(display_id: params[:base_conversation_id])
  end

  def set_mergee_conversation
    @mergee_conversation = conversations.find_by!(display_id: params[:mergee_conversation_id])
  end

  def conversations
    @conversations ||= Current.account.conversations
  end
end
