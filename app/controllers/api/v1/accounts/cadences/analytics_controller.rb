class Api::V1::Accounts::Cadences::AnalyticsController < Api::V1::Accounts::BaseController
  include DateRangeHelper

  before_action :check_authorization

  def summary
    @summary = Cadences::Analytics::SummaryBuilder.new(account: Current.account, filters: filters).build
  end

  def steps
    @steps = Cadences::Analytics::StepsBuilder.new(account: Current.account, filters: filters).build
  end

  def agents
    @agents = Cadences::Analytics::AgentsBuilder.new(account: Current.account, filters: filters).build
  end

  def templates
    @templates = Cadences::Analytics::TemplatesBuilder.new(account: Current.account, filters: filters).build
  end

  def variants
    @variants = Cadences::Analytics::VariantsBuilder.new(account: Current.account, filters: filters).build
  end

  private

  def check_authorization
    authorize(:cadence_analytics, :"#{action_name}?")
  end

  def filters
    {
      range: range,
      inbox_id: params[:inbox_id],
      cadence_definition_id: params[:cadence_definition_id],
      assignee_id: params[:assignee_id],
      team_id: params[:team_id],
      status: params[:status],
      step: params[:step],
      template_key: params[:template_key]
    }
  end
end
