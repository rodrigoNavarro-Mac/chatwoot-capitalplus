class AgentBots::InternalFlowJob < ApplicationJob
  queue_as :high

  def perform(agent_bot_id, payload)
    agent_bot = AgentBot.find_by(id: agent_bot_id)
    return unless agent_bot&.internal_flow?

    message = Message.find_by(id: payload[:id] || payload['id'])
    return unless message
    return unless message.incoming?

    AgentBots::InternalFlowHandlerService.new(agent_bot, message.conversation, message.content.to_s).perform
  rescue StandardError => e
    Rails.logger.error("[AgentBots::InternalFlowJob] Error processing bot #{agent_bot_id}: #{e.message}")
    raise
  end
end
