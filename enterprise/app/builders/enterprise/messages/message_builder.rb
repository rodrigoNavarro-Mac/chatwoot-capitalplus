module Enterprise::Messages::MessageBuilder
  private

  # El chequeo de "canal habilitado para voz" (antes: @conversation.inbox.channel.voice_enabled?)
  # existía para bloquear llamadas EN VIVO enrutadas a un canal que no las soporta. No aplica a
  # Voice::CallMessageBuilder, el único emisor de content_type: 'voice_call' en todo el código
  # (siempre server-side, nunca desde input externo) — incluye llamadas históricas que se
  # registran DESPUÉS de haber terminado (ej. Crm::Aircall::InboundWebhookService, adjuntadas a la
  # conversación de WhatsApp que el contacto ya tenía, no a un canal con voz en vivo).
  def message_type
    return @message_type if @message_type == 'incoming' && @params[:content_type] == 'voice_call'

    super
  end
end
