# Recibe los webhooks de Aircall (call.created/call.answered/call.ended) — ver
# Crm::Aircall::InboundWebhookService. A diferencia de Zoho (que firma con un header,
# X-Zoho-Webhook-Secret), Aircall no ofrece configurar headers personalizados al crear un
# webhook desde su dashboard, así que el secreto va embebido en la propia URL.
class Webhooks::AircallController < ActionController::API
  before_action :find_account
  before_action :verify_secret!

  def process_payload
    Webhooks::AircallEventsJob.perform_later(@account.id, params.to_unsafe_hash)
    head :ok
  end

  private

  def find_account
    @account = Account.find_by(id: params[:account_id])
    head :not_found if @account.blank?
  end

  def verify_secret!
    hook = @account.hooks.find_by(app_id: 'aircall')
    expected_secret = hook&.settings&.dig('webhook_secret')

    head :unauthorized if expected_secret.blank?
    return if performed?

    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected_secret.to_s, params[:secret_token].to_s)
  end
end
