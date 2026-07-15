class Api::V1::Accounts::CadenceEnrollmentsController < Api::V1::Accounts::BaseController
  include DateRangeHelper

  before_action :fetch_cadence_enrollment, only: [:show, :pause, :resume, :cancel]
  before_action :check_authorization

  def index
    @cadence_enrollments = filtered_enrollments.order(created_at: :desc)
  end

  def show; end

  def pause
    @cadence_enrollment.update!(status: :paused_by_response, stopped_reason: 'manual_pause')
  end

  def resume
    @cadence_enrollment.update!(status: :active, stopped_reason: nil)
    Cadences::AdvanceJob.perform_later(@cadence_enrollment.id)
  end

  def cancel
    @cadence_enrollment.cadence_call_tasks.pending.update_all(status: 'skipped') # rubocop:disable Rails/SkipsModelValidations
    @cadence_enrollment.update!(status: :failed, stopped_reason: 'manual_cancel')
  end

  private

  def fetch_cadence_enrollment
    @cadence_enrollment = Current.account.cadence_enrollments.find(params[:id])
  end

  def check_authorization
    authorize(@cadence_enrollment || CadenceEnrollment)
  end

  def filtered_enrollments
    Current.account.cadence_enrollments
           .filter_by_date_range(range)
           .filter_by_inbox_id(permitted_params[:inbox_id])
           .filter_by_cadence_definition_id(permitted_params[:cadence_definition_id])
           .filter_by_assignee_id(permitted_params[:assignee_id])
           .filter_by_team_id(permitted_params[:team_id])
           .filter_by_status(permitted_params[:status])
           .filter_by_step(permitted_params[:step])
  end

  def permitted_params
    params.permit(:inbox_id, :cadence_definition_id, :assignee_id, :team_id, :status, :step)
  end
end
