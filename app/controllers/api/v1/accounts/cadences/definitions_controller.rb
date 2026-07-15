class Api::V1::Accounts::Cadences::DefinitionsController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox, only: [:index, :create]
  before_action :fetch_cadence_definition, only: %i[update destroy]
  before_action :check_authorization

  def index
    @cadence_definitions = @inbox.cadence_definitions.order(:id)
  end

  def create
    is_default = permitted_params[:is_default]
    @cadence_definition = @inbox.cadence_definitions.new(permitted_params.except(:is_default))
    @cadence_definition.account_id = Current.account.id
    @cadence_definition.save!
    @cadence_definition.mark_as_default! if is_default
    @cadence_definitions = @inbox.cadence_definitions.order(:id)
    render :index
  end

  def update
    is_default = permitted_params[:is_default]
    @cadence_definition.update!(permitted_params.except(:is_default))
    @cadence_definition.mark_as_default! if is_default
    @cadence_definitions = @cadence_definition.inbox.cadence_definitions.order(:id)
    render :index
  end

  def destroy
    @cadence_definition.destroy!
    head :no_content
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def fetch_cadence_definition
    @cadence_definition = Current.account.cadence_definitions.find(params[:id])
  end

  def check_authorization
    authorize(CadenceDefinition)
  end

  def permitted_params
    params.permit(:name, :segment_value, :is_default, :active)
  end
end
