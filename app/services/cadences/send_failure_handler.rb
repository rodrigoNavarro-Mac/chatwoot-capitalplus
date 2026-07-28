# Politica compartida de reintento ante un fallo de envio de plantilla, usada tanto por el
# camino sincrono (Cadences::StepExecutor, cuando la llamada HTTP a Meta falla o devuelve
# error) como por el camino asincrono (Whatsapp::IncomingMessageBaseService, cuando Meta
# acepta el envio pero luego reporta status: failed por webhook, ej. el video no paso su
# validacion de descarga). Errores transitorios (timeout de red, rate-limit de Meta, fallo
# de subida/descarga de media) se reintentan solos con backoff creciente; errores
# permanentes (plantilla rechazada, numero invalido, etc.) terminan el enrollment de
# inmediato, igual que antes.
class Cadences::SendFailureHandler
  include Cadences::EventLogger

  # https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/
  # 131053: media upload/download error, 130429: rate limit hit
  TRANSIENT_META_ERROR_CODES = [131_053, 130_429].freeze
  BACKOFF_MINUTES = [2, 5, 15, 30, 60].freeze
  MAX_RETRIES = BACKOFF_MINUTES.size

  # Enlaza un Message fallido (webhook de status asíncrono) con el CadenceEnrollment que lo
  # originó y aplica la misma política de reintento. Vive acá (no en
  # Whatsapp::IncomingMessageBaseService) porque es lógica de dominio de cadencias, no de
  # parseo de webhooks de WhatsApp.
  def self.handle_async_message_failure(message, error)
    enrollment = enrollment_for_failed_message(message)
    return if enrollment.blank?

    # send_step ya avanzó current_step al aceptar el envío (Meta lo confirmó en el momento),
    # pero terminó fallando igual — hay que retroceder un paso para que, al reintentar,
    # StepExecutor vuelva a apuntar al mismo paso que falló en vez de saltar al siguiente.
    enrollment.update!(current_step: enrollment.current_step - 1)
    new(enrollment: enrollment, error_detail: message.external_error, error_code: error&.dig(:code)).call
  end

  def self.enrollment_for_failed_message(message)
    enrollment_id = message.additional_attributes&.dig('cadence_enrollment_id')
    return nil if enrollment_id.blank?

    enrollment = CadenceEnrollment.find_by(id: enrollment_id)
    return nil unless enrollment&.waiting_response? && enrollment.current_step == message.additional_attributes['cadence_step']

    enrollment
  end
  private_class_method :enrollment_for_failed_message

  def initialize(enrollment:, error_detail: nil, error_code: nil, transient: nil)
    @enrollment = enrollment
    @error_detail = error_detail
    @error_code = error_code
    @transient = transient
  end

  def call
    return terminate!('send_failed', error_detail) unless transient?
    return terminate!('send_failed_max_retries', error_detail) if enrollment.send_retry_count >= MAX_RETRIES

    schedule_retry!
  end

  private

  attr_reader :enrollment, :error_detail, :error_code, :transient

  def transient?
    return transient unless transient.nil?

    TRANSIENT_META_ERROR_CODES.include?(error_code.to_i)
  end

  def schedule_retry!
    attempt = enrollment.send_retry_count + 1
    wait_minutes = BACKOFF_MINUTES[attempt - 1]
    # status: :active es un no-op para el camino síncrono (StepExecutor solo llega acá con
    # el enrollment ya en active/pending_agent_call), pero es necesario para el camino
    # asíncrono del webhook, donde el enrollment quedó en waiting_response.
    enrollment.update!(status: :active, send_retry_count: attempt, next_action_at: Time.current + wait_minutes.minutes)
    log_cadence_event(enrollment, 'send_retry_scheduled', metadata: { attempt: attempt, wait_minutes: wait_minutes, detail: error_detail }.compact)
    Cadences::AdvanceJob.set(wait_until: enrollment.next_action_at).perform_later(enrollment.id)
  end

  def terminate!(reason, detail)
    stopped_reason = detail.present? ? "#{reason}: #{detail}".truncate(500) : reason
    enrollment.update!(status: :failed, stopped_reason: stopped_reason)
    log_cadence_event(enrollment, 'cadence_failed', metadata: { reason: reason, detail: detail }.compact)
  end
end
