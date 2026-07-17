class Webhooks::ZohoCrmController < ActionController::API
  before_action :find_account
  before_action :verify_zoho_secret!

  def process_payload
    Webhooks::ZohoCrmEventsJob.perform_later(@account.id, params.to_unsafe_hash)
    head :ok
  end

  def send_template
    Crm::Zoho::SendInitialTemplateService.new(@account, send_template_params).perform
    render json: { status: 'ok' }
  rescue Whatsapp::TemplateValidationError => e
    render json: { error: 'invalid_template_payload', details: e.details }, status: :unprocessable_entity
  rescue Crm::Zoho::TemplateSendError => e
    render json: { error: 'template_send_failed', meta_error: e.meta_error }.compact, status: e.http_status
  rescue RuntimeError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def send_template_params
    permitted = params.permit(
      :phone, :contact_name, :desarrollo, :template_name, :template_language, :assignee_email,
      :header_image_url, :header_video_url, :header_document_url, :header_document_filename, :header_text
    ).to_h

    permitted.merge(
      'header' => deep_unsafe(params[:header]),
      'header_location' => deep_unsafe(params[:header_location]),
      'body_params' => deep_unsafe(params[:body_params]),
      'button_params' => deep_unsafe(params[:button_params])
    ).with_indifferent_access
  end

  # header/body_params/button_params accept heterogeneous, type-dependent shapes (a body param
  # can be a string, a currency hash, a date_time hash, ...) that don't fit a static `permit`
  # whitelist. This webhook is already gated by verify_zoho_secret!, so we allow these specific,
  # known fields through unfiltered rather than permitting the whole request.
  def deep_unsafe(value)
    case value
    when ActionController::Parameters
      value.to_unsafe_h
    when Array
      value.map { |v| deep_unsafe(v) }
    else
      value
    end
  end

  def find_account
    account_id = params[:account_id]
    @account = Account.find_by(id: account_id)
    head :not_found if @account.blank?
  end

  def verify_zoho_secret!
    hook = @account.hooks.find_by(app_id: 'zoho_crm')
    expected_secret = hook&.settings&.dig('webhook_secret')

    return if expected_secret.blank?

    provided = request.headers['X-Zoho-Webhook-Secret']
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected_secret.to_s, provided.to_s)
  end
end
