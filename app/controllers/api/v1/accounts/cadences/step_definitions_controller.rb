class Api::V1::Accounts::Cadences::StepDefinitionsController < Api::V1::Accounts::BaseController
  before_action :fetch_cadence_definition
  before_action :check_authorization
  before_action :fetch_step_definition, only: [:update, :destroy]

  def index
    @step_definitions = @cadence_definition.cadence_step_definitions.ordered
  end

  def create
    @step_definition = @cadence_definition.cadence_step_definitions.new(permitted_params)
    @step_definition.position = next_position
    @step_definition.template_key = generate_template_key if @step_definition.template_key.blank?
    @step_definition.save!
    @step_definitions = @cadence_definition.cadence_step_definitions.ordered
    render :index
  end

  def update
    @step_definition.update!(permitted_params)
    @step_definitions = @cadence_definition.cadence_step_definitions.ordered
    render :index
  end

  def destroy
    ActiveRecord::Base.transaction do
      position = @step_definition.position
      @step_definition.destroy!
      @cadence_definition.cadence_step_definitions.where('position > ?', position).order(:position).each do |step_definition|
        step_definition.update!(position: step_definition.position - 1)
      end
    end
    head :no_content
  end

  def reorder
    ActiveRecord::Base.transaction do
      definitions = ordered_ids.map { |id| @cadence_definition.cadence_step_definitions.find(id) }
      # Dos pasadas: la posición es única por cadence_definition, así que reasignar directo
      # puede chocar a mitad de camino con la posición todavía vigente de otro paso (ej. swap
      # 1<->2). Pasamos primero por valores negativos (nunca colisionan entre sí ni con los
      # actuales) y luego asignamos las posiciones finales.
      # update_columns: la posición temporal negativa no debe pasar por la validación
      # numericality (greater_than: 0), que solo aplica al estado final.
      # rubocop:disable Rails/SkipsModelValidations
      definitions.each_with_index { |step_definition, index| step_definition.update_columns(position: -(index + 1)) }
      # rubocop:enable Rails/SkipsModelValidations
      # rubocop:disable Style/CombinableLoops -- a propósito: debe completarse la pasada
      # negativa completa antes de empezar la pasada final, si no se reintroduce el choque.
      definitions.each_with_index { |step_definition, index| step_definition.update!(position: index + 1) }
      # rubocop:enable Style/CombinableLoops
    end
    @step_definitions = @cadence_definition.cadence_step_definitions.ordered
    render :index
  end

  private

  def fetch_cadence_definition
    @cadence_definition = Current.account.cadence_definitions.find(params[:cadence_definition_id])
  end

  def fetch_step_definition
    @step_definition = @cadence_definition.cadence_step_definitions.find(params[:id])
  end

  def check_authorization
    authorize(CadenceStepDefinition)
  end

  def next_position
    (@cadence_definition.cadence_step_definitions.maximum(:position) || 0) + 1
  end

  def generate_template_key
    "step_#{SecureRandom.hex(4)}"
  end

  def ordered_ids
    params.require(:ordered_ids)
  end

  def permitted_params
    params.permit(
      :label, :template_key, :template_name, :template_language, :template_namespace,
      :schedule_type, :offset_minutes, :day_offset, :time_of_day, :wait_window_minutes,
      :creates_call_task, :active, :media_url, :media_type, :media_name,
      body_variables: {}
    )
  end
end
