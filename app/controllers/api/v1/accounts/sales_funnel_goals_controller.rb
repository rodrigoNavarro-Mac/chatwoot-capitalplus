class Api::V1::Accounts::SalesFunnelGoalsController < Api::V1::Accounts::BaseController
  before_action :fetch_sales_funnel_goal, only: %i[update destroy]
  before_action :check_authorization

  def index
    @sales_funnel_goals = filtered_goals
  end

  def create
    Current.account.sales_funnel_goals.create!(permitted_params)
    @sales_funnel_goals = all_goals
    render :index
  end

  def update
    @sales_funnel_goal.update!(permitted_params)
    @sales_funnel_goals = all_goals
    render :index
  end

  def destroy
    @sales_funnel_goal.destroy!
    head :no_content
  end

  private

  # create/update devuelven la lista completa (no la filtrada por los params de esa request
  # puntual) para que el frontend pueda reemplazar su tabla sin perder de vista otros
  # desarrollos/meses que tenía cargados.
  def all_goals
    Current.account.sales_funnel_goals.order(:period_month, :development_key, :stage)
  end

  def filtered_goals
    scope = Current.account.sales_funnel_goals
    scope = scope.where(development_key: params[:development_key]) if params[:development_key].present?
    scope = scope.where(period_month: parsed_period_month) if params[:period_month].present?
    scope.order(:period_month, :development_key, :stage)
  end

  def parsed_period_month
    Date.parse(params[:period_month]).beginning_of_month
  rescue ArgumentError, TypeError
    nil
  end

  def fetch_sales_funnel_goal
    @sales_funnel_goal = Current.account.sales_funnel_goals.find(params[:id])
  end

  def permitted_params
    params.permit(:development_key, :stage, :period_month, :target_percent)
  end

  def check_authorization
    authorize(SalesFunnelGoal)
  end
end
