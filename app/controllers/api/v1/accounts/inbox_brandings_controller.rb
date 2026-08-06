class Api::V1::Accounts::InboxBrandingsController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :check_authorization

  def show
    @branding = @inbox.report_branding
  end

  def update
    @branding = @inbox.report_branding || @inbox.build_report_branding(account: Current.account)
    @branding.assign_attributes(permitted_params)
    @branding.save!
    render :show
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def check_authorization
    authorize(Reports::InboxBranding)
  end

  def permitted_params
    params.permit(:accent_color, :logo, :letterhead_template)
  end
end
