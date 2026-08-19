class Api::V1::Accounts::CadenceCallTasksController < Api::V1::Accounts::BaseController
  before_action :fetch_cadence_call_task, only: [:complete]
  before_action :check_authorization

  def index
    @cadence_call_tasks = filtered_tasks.order(created_at: :desc)
  end

  def complete
    @cadence_call_task.complete!(Current.user)
    log_call_completed
  end

  private

  def fetch_cadence_call_task
    @cadence_call_task = Current.account.cadence_call_tasks.find(params[:id])
  end

  def check_authorization
    authorize(@cadence_call_task || CadenceCallTask)
  end

  def filtered_tasks
    scope = Current.account.cadence_call_tasks.filter_by_status(permitted_params[:status])
    scope = scope.filter_by_user_id(permitted_params[:user_id]) if permitted_params[:user_id].present?
    scope = scope.own_or_team(Current.user) unless unrestricted_cadence_access?
    scope
  end

  def permitted_params
    params.permit(:status, :user_id)
  end

  def unrestricted_cadence_access?
    Current.account_user.administrator? || Current.account_user.custom_role&.permissions&.include?('cadence_manage')
  end

  def log_call_completed
    enrollment = @cadence_call_task.cadence_enrollment
    CadenceEvent.create!(
      account_id: enrollment.account_id,
      cadence_enrollment_id: enrollment.id,
      conversation_id: enrollment.conversation_id,
      contact_id: enrollment.contact_id,
      event_type: 'call_completed',
      step: @cadence_call_task.step,
      actor_type: 'User',
      actor_id: Current.user.id
    )
  end
end
