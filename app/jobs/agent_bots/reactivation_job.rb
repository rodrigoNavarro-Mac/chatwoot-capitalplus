class AgentBots::ReactivationJob < ApplicationJob
  queue_as :scheduled_jobs

  # Rango en horas desde el último mensaje del bot en que se dispara la reactivación.
  # Con ventana de 24h de Meta, buscamos conversaciones entre 20 y 23h sin respuesta.
  REACTIVATION_WINDOW = (20.hours.ago..23.hours.ago).freeze

  def perform
    bot_map = active_internal_flow_bots
    return if bot_map.empty?

    stale_conversations(bot_map.keys).each do |conversation|
      agent_bot = bot_map[conversation.inbox_id]
      next unless reactivation_enabled?(agent_bot)
      next unless bot_is_waiting?(conversation)
      next if already_reactivated?(conversation)

      send_reactivation(conversation, agent_bot)
    rescue StandardError => e
      Rails.logger.error(
        "[AgentBots::ReactivationJob] conversation=#{conversation.id} error=#{e.message}"
      )
    end
  end

  private

  # Devuelve { inbox_id => agent_bot } para todos los inboxes con bot internal_flow activo.
  def active_internal_flow_bots
    AgentBotInbox.active
                 .joins(:agent_bot)
                 .where(agent_bots: { bot_type: 'internal_flow' })
                 .each_with_object({}) do |abi, hash|
                   hash[abi.inbox_id] = abi.agent_bot
                 end
  end

  # Conversaciones abiertas, sin agente asignado, cuya última actividad
  # cayó en la ventana de reactivación (20-23h atrás).
  def stale_conversations(inbox_ids)
    Conversation.open
                .where(inbox_id: inbox_ids)
                .where(assignee_id: nil)
                .where(last_activity_at: 23.hours.ago..20.hours.ago)
  end

  # El último mensaje debe ser saliente del bot y el paso actual debe estar activo.
  def bot_is_waiting?(conversation)
    last_outgoing = conversation.messages
                                .where(message_type: :outgoing)
                                .order(:created_at)
                                .last
    return false unless last_outgoing&.sender_type == 'AgentBot'

    conversation.custom_attributes['_bot_current_step'].present?
  end

  def reactivation_enabled?(agent_bot)
    config = agent_bot.bot_config.with_indifferent_access
    config.dig(:reactivation, :enabled) == true
  end

  # Evita mandar el mensaje más de una vez si el job corre varias veces
  # dentro de la misma ventana de 3h.
  def already_reactivated?(conversation)
    conversation.custom_attributes['_bot_reactivated_at'].present?
  end

  def send_reactivation(conversation, agent_bot)
    config  = agent_bot.bot_config.with_indifferent_access
    message = config.dig(:reactivation, :message).to_s.strip
    return if message.blank?

    params = {
      content:      message,
      private:      false,
      message_type: 'outgoing',
      sender_type:  'AgentBot',
      sender_id:    agent_bot.id,
    }

    Messages::MessageBuilder.new(nil, conversation, params).perform

    # Marca para no reactivar dos veces en la misma ventana
    updated_attrs = conversation.custom_attributes.merge(
      '_bot_reactivated_at' => Time.current.iso8601
    )
    conversation.update!(custom_attributes: updated_attrs)

    Rails.logger.info(
      "[AgentBots::ReactivationJob] Reactivation sent conversation=#{conversation.id} bot=#{agent_bot.id}"
    )
  end
end
