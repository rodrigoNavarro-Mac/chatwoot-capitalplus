class Webhooks::ZohoCrmController < ActionController::API
  before_action :find_account
  before_action :verify_zoho_secret!

  def process_payload
    Webhooks::ZohoCrmEventsJob.perform_later(@account.id, params.to_unsafe_hash)
    head :ok
  end

  def send_template
    Crm::Zoho::SendInitialTemplateService.new(@account, params).perform
    render json: { status: 'ok' }
  rescue RuntimeError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

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
