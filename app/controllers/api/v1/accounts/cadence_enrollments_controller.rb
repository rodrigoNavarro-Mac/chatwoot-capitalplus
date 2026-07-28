class Api::V1::Accounts::CadenceEnrollmentsController < Api::V1::Accounts::BaseController
  include DateRangeHelper

  before_action :fetch_cadence_enrollment, only: [:show, :pause, :resume, :cancel]
  before_action :fetch_conversation, only: [:create]
  before_action :check_authorization

  def index
    @cadence_enrollments = filtered_enrollments.order(created_at: :desc)
  end

  def show; end

  # Inscribe manualmente una conversación elegible en la cadencia que le corresponda por
  # CadenceDefinitionResolver (mismo reparto/segmento que usaría el enroll automático al
  # asignarla) — no permite forzar una variante específica.
  def create
    return render_enrollment_error('already_enrolled') if CadenceEnrollment.exists?(conversation_id: @conversation.id)
    return render_enrollment_error('not_eligible') unless Cadences::EligibilityChecker.new(conversation: @conversation).eligible?

    @cadence_enrollment = Cadences::EnrollmentService.new(conversation: @conversation).enroll!
    render_enrollment_error('cadence_not_configured') if @cadence_enrollment.blank?
  end

  # Conversaciones candidatas para el modal de "Enrolar manualmente": mismos criterios que
  # Cadences::EligibilityChecker, sin repetirlos, para que nunca se pueda elegir algo que
  # #create luego rechazaría.
  def eligible_conversations
    @conversations = eligible_conversations_scope
  end

  # Inscripción masiva: dispara Cadences::EnrollPastLeadsJob en segundo plano para todas las
  # conversaciones de WhatsApp de la cuenta (o de un inbox puntual) que ya recibieron mensajes
  # pero nunca quedaron enroladas en cadencia — mismo criterio que el rake task
  # cadences:enroll_past_leads, pero disparable desde el botón del dashboard.
  def enroll_past_leads
    Cadences::EnrollPastLeadsJob.perform_later(Current.account.id, inbox_id: params[:inbox_id].presence)
    render json: { enqueued: true }
  end

  def pause
    @cadence_enrollment.update!(status: :paused_by_response, stopped_reason: 'manual_pause')
  end

  def resume
    refresh_steps_snapshot!(@cadence_enrollment) if @cadence_enrollment.failed? || @cadence_enrollment.cold?
    @cadence_enrollment.update!(status: :active, stopped_reason: nil, next_action_at: Time.current, send_retry_count: 0)
    Cadences::AdvanceJob.set(wait_until: Time.current).perform_later(@cadence_enrollment.id)
  end

  # Reintento masivo: reactiva todos los enrollments "failed" que coincidan con los filtros
  # actuales del listado (mismos filtros que #index) y vuelve a encolar su siguiente paso.
  def retry_failed
    failed_enrollments = filtered_enrollments.failed.to_a
    failed_enrollments.each do |enrollment|
      refresh_steps_snapshot!(enrollment)
      enrollment.update!(status: :active, stopped_reason: nil, next_action_at: Time.current, send_retry_count: 0)
      Cadences::AdvanceJob.set(wait_until: Time.current).perform_later(enrollment.id)
    end
    render json: { retried: failed_enrollments.size }
  end

  def cancel
    @cadence_enrollment.cadence_call_tasks.pending.update_all(status: 'skipped') # rubocop:disable Rails/SkipsModelValidations
    @cadence_enrollment.update!(status: :failed, stopped_reason: 'manual_cancel')
  end

  private

  def fetch_cadence_enrollment
    @cadence_enrollment = Current.account.cadence_enrollments.find(params[:id])
  end

  def fetch_conversation
    @conversation = Current.account.conversations.find(create_params[:conversation_id])
  end

  def check_authorization
    authorize(@cadence_enrollment || CadenceEnrollment)
  end

  def render_enrollment_error(reason)
    render json: { error: reason }, status: :unprocessable_entity
  end

  # Un enrollment failed pudo haber fallado por un paso mal configurado (media_url/media_type
  # equivocado, etc.) que ya se corrigió en Configuración → Cadencia → Pasos, y un cold pudo
  # haber agotado los pasos que existían antes de que se agregara uno nuevo. steps_snapshot
  # queda congelado desde el enroll! original (ver Cadences::StepsRepository), así que sin este
  # refresh el retry repetiría el mismo error (o no vería el paso nuevo) para siempre.
  def refresh_steps_snapshot!(enrollment)
    snapshot = Cadences::StepsRepository.snapshot_for(enrollment.cadence_definition)
    enrollment.update!(steps_snapshot: snapshot) if snapshot.present?
  end

  def eligible_conversations_scope
    candidates = Current.account.conversations
                        .joins(:inbox, :contact)
                        .where(inboxes: { channel_type: 'Channel::Whatsapp' })
                        .open.assigned
                        .where.not(id: CadenceEnrollment.select(:conversation_id))
    candidates = apply_conversation_search(candidates)
    candidates.includes(:assignee, :inbox, :contact).order(created_at: :desc).limit(200)
              .select { |conversation| Cadences::EligibilityChecker.new(conversation: conversation).eligible? }
              .first(20)
  end

  def apply_conversation_search(scope)
    query = params[:q].to_s.strip
    return scope if query.blank?

    if query.match?(/\A\d+\z/)
      scope.where(display_id: query.to_i)
    else
      scope.where('contacts.name ILIKE :q OR contacts.phone_number ILIKE :q', q: "%#{query}%")
    end
  end

  def create_params
    params.permit(:conversation_id)
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
