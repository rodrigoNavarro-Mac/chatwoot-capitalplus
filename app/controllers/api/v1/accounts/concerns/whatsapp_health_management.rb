module Api::V1::Accounts::Concerns::WhatsappHealthManagement
  extend ActiveSupport::Concern

  included do
    skip_before_action :check_authorization, only: [:health, :register_webhook]
    before_action :check_admin_authorization?, only: [:register_webhook, :assign_whatsapp_template, :unassign_whatsapp_template]
    before_action :validate_whatsapp_cloud_channel, only: [:health, :register_webhook]
  end

  def sync_templates
    return render status: :unprocessable_entity, json: { error: 'Template sync is only available for WhatsApp channels' } unless whatsapp_channel?

    trigger_template_sync
    render status: :ok, json: { message: 'Template sync initiated successfully' }
  rescue StandardError => e
    render status: :internal_server_error, json: { error: e.message }
  end

  def message_templates
    unless whatsapp_channel?
      return render status: :unprocessable_entity, json: { error: 'Message templates are only available for WhatsApp channels' }
    end

    templates, last_sync_attempt_at, name_key = message_template_data
    templates = templates.select { |template| template[name_key] == params[:name] } if params[:name].present?

    render json: {
      payload: templates,
      meta: { last_sync_attempt_at: last_sync_attempt_at }
    }
  end

  def health
    health_data = Whatsapp::HealthService.new(@inbox.channel).sync_health_status!(include_business_profile: true)
    render json: health_data
  rescue Whatsapp::HealthService::ApiError => e
    Rails.logger.error "[INBOX HEALTH] Error fetching health data: #{e.message}"
    render json: {
      error: {
        type: e.authorization_error? ? 'authorization' : 'api',
        message: e.message,
        http_status: e.http_status,
        code: e.code,
        subcode: e.subcode
      }.compact
    }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "[INBOX HEALTH] Error fetching health data: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def register_webhook
    Whatsapp::WebhookSetupService.new(@inbox.channel).register_callback

    render json: { message: 'Webhook registered successfully' }, status: :ok
  rescue StandardError => e
    Rails.logger.error "[INBOX WEBHOOK] Webhook registration failed: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def assign_whatsapp_template
    return render status: :unprocessable_entity, json: { error: 'Template name is required' } if params[:template_name].blank?

    assignment = @inbox.whatsapp_template_inbox_assignments.find_or_create_by!(
      account_id: @inbox.account_id,
      template_name: params[:template_name]
    )
    assignment.update!(assignment_media_params) if params.key?(:media_url) || params.key?(:media_name)
    render 'api/v1/accounts/inboxes/show'
  rescue ActiveRecord::RecordInvalid => e
    render status: :unprocessable_entity, json: { error: e.message }
  end

  def unassign_whatsapp_template
    @inbox.whatsapp_template_inbox_assignments.where(template_name: params[:template_name]).destroy_all
    render 'api/v1/accounts/inboxes/show'
  end

  def whatsapp_business_management_token
    Whatsapp::BusinessManagementTokenService.new(whatsapp_channel).update!(params.require(:business_management_token))

    head :no_content
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { error: e.message, message: e.message }, status: :unprocessable_entity
  end

  private

  def assignment_media_params
    {
      media_url: params[:media_url].presence,
      media_name: params[:media_name].presence
    }
  end

  def whatsapp_channel
    channel = @inbox.channel
    raise ActiveRecord::RecordNotFound unless channel.is_a?(Channel::Whatsapp)

    channel
  end

  def validate_whatsapp_cloud_channel
    return if @inbox.channel.is_a?(Channel::Whatsapp) && @inbox.channel.provider == 'whatsapp_cloud'

    render json: { error: 'Health data only available for WhatsApp Cloud API channels' }, status: :bad_request
  end

  def whatsapp_channel?
    @inbox.whatsapp? || (@inbox.twilio? && @inbox.channel.whatsapp?)
  end

  def message_template_data
    return [@inbox.channel.message_templates.presence || [], @inbox.channel.message_templates_last_updated, 'name'] unless @inbox.twilio_whatsapp?

    [@inbox.channel.content_templates&.dig('templates') || [], @inbox.channel.content_templates_last_updated, 'friendly_name']
  end

  def trigger_template_sync
    if @inbox.whatsapp?
      Channels::Whatsapp::TemplatesSyncJob.perform_later(@inbox.channel)
    elsif @inbox.twilio? && @inbox.channel.whatsapp?
      Channels::Twilio::TemplatesSyncJob.perform_later(@inbox.channel)
    end
  end
end
