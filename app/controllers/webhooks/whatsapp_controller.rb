class Webhooks::WhatsappController < ActionController::API
  include MetaTokenVerifyConcern

  # Runs before signature verification so the raw payload is captured even when
  # the request gets rejected downstream (bad signature, unresolved channel, etc.)
  before_action :log_raw_webhook_event, only: :process_payload
  before_action :verify_meta_signature!, only: :process_payload

  def process_payload
    if inactive_whatsapp_number?
      Rails.logger.warn("Rejected webhook for inactive WhatsApp number: #{params[:phone_number]}")
      render json: { error: 'Inactive WhatsApp number' }, status: :unprocessable_entity
      return
    end

    Webhooks::WhatsappEventsJob.perform_later(params.to_unsafe_hash)
    head :ok
  end

  private

  def log_raw_webhook_event
    metadata = params.dig(:entry, 0, :changes, 0, :value, :metadata) || {}

    WhatsappWebhookEvent.create!(
      phone_number: params[:phone_number] || normalized_phone_number(metadata[:display_phone_number]),
      phone_number_id: metadata[:phone_number_id],
      payload: params.to_unsafe_hash.except('controller', 'action')
    )
  rescue StandardError => e
    Rails.logger.error "Failed to persist raw WhatsApp webhook event: #{e.message}"
  end

  def valid_token?(token)
    if params[:phone_number].present?
      channel = Channel::Whatsapp.find_by(phone_number: params[:phone_number])
      token == channel&.provider_config&.dig('webhook_verify_token')
    else
      token == GlobalConfigService.load('WHATSAPP_WEBHOOK_VERIFY_TOKEN', nil)
    end
  end

  def meta_app_secrets
    [
      *channel_meta_app_secrets(whatsapp_channel),
      GlobalConfigService.load('WHATSAPP_APP_SECRET', nil)
    ]
  end

  def whatsapp_channel
    @whatsapp_channel ||= whatsapp_business_payload_channel || Channel::Whatsapp.find_by(phone_number: params[:phone_number])
  end

  def meta_signature_verification_required?
    return true if whatsapp_channel.blank?
    return false unless whatsapp_channel.provider == 'whatsapp_cloud'
    return true if channel_meta_app_secrets(whatsapp_channel).present?

    whatsapp_channel.provider_config['source'] == 'embedded_signup'
  end

  def whatsapp_business_payload_channel
    return unless params[:object] == 'whatsapp_business_account'

    metadata = params.dig(:entry, 0, :changes, 0, :value, :metadata)
    return if metadata.blank?

    phone_number_id = metadata[:phone_number_id]
    return if phone_number_id.blank?

    Channel::Whatsapp.find_by("provider_config ->> 'phone_number_id' = ?", phone_number_id)
  end

  def inactive_whatsapp_number?
    phone_number = params[:phone_number]
    return false if phone_number.blank?

    inactive_numbers = GlobalConfig.get_value('INACTIVE_WHATSAPP_NUMBERS').to_s
    return false if inactive_numbers.blank?

    inactive_numbers_array = inactive_numbers.split(',').map(&:strip)
    inactive_numbers_array.include?(phone_number)
  end
end
