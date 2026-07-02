class Crm::Zoho::Mappers::ConversationMapper
  NOTE_CONTENT_MAX_SIZE = 3000

  def self.conversation_note(conversation)
    new(conversation).conversation_note
  end

  def self.transcript_note(conversation)
    new(conversation).transcript_note
  end

  def initialize(conversation)
    @conversation = conversation
  end

  def conversation_note
    safe_conversation_url
  end

  def transcript_note
    safe_conversation_url
  end

  private

  attr_reader :conversation

  def transcript_messages
    @conversation.messages.chat.select(&:conversation_transcriptable?)
  end

  def format_messages(messages)
    lines = []
    current_size = 0

    messages.reverse_each do |msg|
      line = "[#{msg.created_at.strftime('%Y-%m-%d %H:%M')}] #{sender_name(msg)}: #{msg.content.presence || '(sin contenido)'}"
      break if current_size + line.length > NOTE_CONTENT_MAX_SIZE

      lines << line
      current_size += line.length + 1
    end

    lines.join("\n")
  end

  def sender_name(message)
    return 'Sistema' if message.sender.nil?

    message.sender.name.presence || "#{message.sender_type}##{message.sender_id}"
  end

  def safe_conversation_url
    frontend_url = ENV['FRONTEND_URL'].presence
    return '' if frontend_url.blank?

    "#{frontend_url.chomp('/')}/app/accounts/#{@conversation.account_id}/conversations/#{@conversation.display_id}"
  rescue StandardError
    ''
  end

  def brand_name
    ::GlobalConfig.get('BRAND_NAME')['BRAND_NAME'].presence || 'Chatwoot'
  end
end
