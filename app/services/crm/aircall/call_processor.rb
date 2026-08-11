# Refleja una sola llamada de Aircall como un Message real (content_type: 'voice_call') en la
# conversación más antigua del contacto — reusa Voice::CallMessageBuilder/Call
# (enterprise/app/services/voice, enterprise/app/models/call.rb), la misma arquitectura ya usada
# para llamadas de Twilio, así V2::Reports::SalesFunnelBuilder cuenta el lead como
# "customer_replied" sin necesitar ningún cambio ahí — ya solo mira si existe un Message
# `message_type: incoming` en la conversación.
#
# Recibe un único call object de Aircall (mismo shape tanto si viene del webhook `call.ended`
# como de una fila del endpoint histórico `GET /v1/calls`) y lo procesa de forma idéntica — lo
# usan tanto Crm::Aircall::InboundWebhookService (tiempo real) como
# Crm::Aircall::CallHistoryBackfillService (backfill histórico).
#
# No crea ningún ContactInbox/Conversation nuevo (a diferencia de Voice::InboundCallBuilder,
# pensado para llamadas EN VIVO que sí necesitan una conversación): si el contacto no tiene
# ninguna conversación existente, la llamada se ignora — sin conversación no hay forma de que
# cuente en el embudo de todas formas.
class Crm::Aircall::CallProcessor
  ANONYMOUS_DIGITS = 'anonymous'.freeze

  def initialize(account:, call_data:)
    @account = account
    @data = call_data.with_indifferent_access
  end

  def perform
    return if raw_digits.blank? || raw_digits == ANONYMOUS_DIGITS

    contact = find_contact
    return if contact.blank?

    conversation = contact.conversations.order(:created_at).first
    return if conversation.blank?

    call = find_or_initialize_call(conversation, contact)
    apply_call_attributes!(call)
    persist!(call)

    message = Voice::CallMessageBuilder.new(call).perform!
    call.update!(message_id: message.id) if call.message_id != message.id
  end

  private

  attr_reader :account, :data

  def raw_digits
    data[:raw_digits].to_s
  end

  def aircall_call_id
    data[:id].to_s
  end

  def find_contact
    account.contacts.where(phone_number: phone_variants).first
  end

  def phone_variants
    digits = raw_digits
    with_plus = digits.start_with?('+') ? digits : "+#{digits}"
    [with_plus, digits.delete_prefix('+')].uniq
  end

  def find_or_initialize_call(conversation, contact)
    Call.find_by_provider_call_id(:aircall, aircall_call_id) ||
      Call.new(account: account, inbox: conversation.inbox, conversation: conversation, contact: contact,
               provider: :aircall, provider_call_id: aircall_call_id)
  end

  def apply_call_attributes!(call)
    call.direction = direction
    call.status = status
    call.started_at = started_at
    call.duration_seconds = duration
    call.accepted_by_agent = resolve_agent
    call.ended_at = data[:ended_at] if data[:ended_at].present?
  end

  def persist!(call)
    call.save!
  rescue ActiveRecord::RecordNotUnique
    existing = Call.find_by_provider_call_id(:aircall, aircall_call_id)
    raise if existing.blank?
  end

  def direction
    data[:direction] == 'outbound' ? :outgoing : :incoming
  end

  def status
    data[:answered_at].present? ? 'completed' : 'no_answer'
  end

  def started_at
    ts = data[:started_at]
    Time.zone.at(ts.to_i) if ts.present?
  end

  def duration
    data[:duration]&.to_i
  end

  # El agente de Aircall que atendió/hizo la llamada — se guarda en accepted_by_agent
  # independientemente de la dirección (Voice::CallMessageBuilder solo lo usa como remitente del
  # mensaje si es saliente, pero es información útil de todas formas para llamadas entrantes).
  def resolve_agent
    agent_data = data[:user] || data[:assigned_to]
    email = agent_data.is_a?(Hash) ? agent_data[:email] : nil
    return nil if email.blank?

    user = User.from_email(email)
    user if user && account.users.exists?(id: user.id)
  end
end
