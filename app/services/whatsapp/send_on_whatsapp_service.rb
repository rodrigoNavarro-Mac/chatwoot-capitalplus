class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Whatsapp
  end

  def perform_reply
    return send_template_message if template_params.present?
    return send_session_message if message.conversation.can_reply?

    message.update!(status: :failed, external_error: I18n.t('errors.whatsapp.message_outside_messaging_window'))
  end

  def send_template_message
    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params,
      message: message
    )

    name, namespace, lang_code, processed_parameters = processor.call

    if name.blank?
      message.update!(status: :failed, external_error: 'Template not found or invalid template name')
      return
    end

    message_id = channel.send_template(whatsapp_recipient, {
                                         name: name,
                                         namespace: namespace,
                                         lang_code: lang_code,
                                         parameters: processed_parameters
                                       }, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def send_session_message
    message_id = channel.send_message(whatsapp_recipient, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def whatsapp_recipient
    source_id = message.conversation.contact_inbox.source_id.to_s
    return source_id if source_id.match?(/\A\d{1,15}\z/)

    message.conversation.contact.phone_number.to_s.delete('+').presence || source_id
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end
end
