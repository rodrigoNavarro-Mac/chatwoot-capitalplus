# Resuelve la Account desde un `state` firmado (GlobalID sgid, ver
# Api::V1::Accounts::OauthAuthorizationController#state) — compartido entre OauthCallbackController
# (que además arma un inbox/canal de email) y Zoho::CallbacksController (que no necesita nada de
# eso, solo la cuenta) para no duplicar esta lógica de resolución.
module AccountFromSignedIdConcern
  extend ActiveSupport::Concern

  private

  def account_from_signed_id
    raise ActionController::BadRequest, 'Missing state variable' if params[:state].blank?

    if (account = GlobalID::Locator.locate_signed(params[:state], for: 'onboarding'))
      @return_to = 'onboarding'
    else
      account = GlobalID::Locator.locate_signed(params[:state])
    end

    raise 'Invalid or expired state' if account.nil?

    account
  end

  def account
    @account ||= account_from_signed_id
  end

  def return_to
    account # resolving the sgid records which purpose matched
    @return_to
  end
end
