class Api::V1::Accounts::QuoteDevelopmentRulesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_quote_development_rule, only: [:update, :destroy]

  def index
    @quote_development_rules = Current.account.quote_development_rules.ordered
  end

  def create
    @quote_development_rule = Current.account.quote_development_rules.create!(quote_development_rule_params)
    render :show
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    @quote_development_rule.update!(quote_development_rule_params)
    render :show
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @quote_development_rule.destroy!
    head :no_content
  end

  private

  def check_authorization
    authorize(QuoteDevelopmentRule)
  end

  def fetch_quote_development_rule
    @quote_development_rule = Current.account.quote_development_rules.find(params[:id])
  end

  def quote_development_rule_params
    params.permit(:desarrollo, :msi_auto_max_plazo)
  end
end
