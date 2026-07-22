# Crea el Attachment (URL externa, sin ActiveStorage) que hace que el header media de un
# template WhatsApp (imagen/video/documento) se vea como preview en el chat. El frontend arma
# la burbuja de Image/File/Video a partir de message.attachments, nunca del media_url que viaja
# en additional_attributes.template_params — sin este Attachment, el mensaje aparece sin preview
# aunque WhatsApp sí haya recibido y enviado el archivo.
class Whatsapp::TemplateHeaderAttachmentService
  MEDIA_TYPE_TO_ATTACHMENT_TYPE = { 'image' => :image, 'video' => :video, 'document' => :file }.freeze

  pattr_initialize [:message!, :media_url, :media_type]

  def call
    return if media_url.blank?

    attachment_type = MEDIA_TYPE_TO_ATTACHMENT_TYPE[media_type.to_s]
    return if attachment_type.blank?

    message.attachments.create!(account_id: message.account_id, file_type: attachment_type, external_url: media_url)
  end
end
