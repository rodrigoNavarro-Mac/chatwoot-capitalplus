module AgentBots
  class MessageInterpolator
    def self.call(text, config:, conversation:)
      variables = config[:variables] || {}
      result = variables.reduce(text.to_s) { |msg, (key, value)| msg.gsub("{{#{key}}}", value.to_s) }
      conversation.custom_attributes.each do |key, value|
        next if key.to_s.start_with?('_')

        result = result.gsub("{{#{key}}}", value.to_s)
      end
      result.gsub(/\{\{[^}]+\}\}/, '')
    end
  end
end
