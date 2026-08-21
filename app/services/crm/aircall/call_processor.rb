# Refleja una sola llamada de Aircall como un Message real (content_type: 'voice_call') en la
# conversación más antigua del contacto en el inbox correcto (ver #find_conversation) — reusa
# Voice::CallMessageBuilder/Call
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
  LOCAL_NUMBER_LENGTH = 10

  def initialize(account:, call_data:)
    @account = account
    @data = call_data.with_indifferent_access
  end

  def perform
    return if raw_digits.blank? || raw_digits == ANONYMOUS_DIGITS

    contact = find_contact
    return if contact.blank?

    conversation = find_conversation(contact)
    return if conversation.blank?

    call = find_or_initialize_call(conversation, contact)
    apply_call_attributes!(call)
    persist!(call)

    create_message_without_corrupting_conversation_activity!(call, conversation)
  end

  private

  attr_reader :account, :data

  # Voice::CallMessageBuilder fecha el mensaje con call.started_at (la fecha real de la llamada,
  # casi siempre en el pasado) en vez de "ahora" — necesario para que el historial backfilled no
  # quede todo fechado el día en que corrió el backfill. Pero los callbacks normales de Message
  # (Message#set_conversation_activity, Message#set_waiting_since_on_incoming_message) asumen que
  # todo mensaje nace en tiempo real y "rebobinarían" conversation.last_activity_at/waiting_since a
  # esa fecha pasada, aunque la conversación haya tenido actividad real más reciente — así que se
  # revierten aquí, acotado solo a este flujo, en vez de tocar el modelo Message (que sí necesita
  # poder crear mensajes con created_at pasado libremente, ej. en specs).
  def create_message_without_corrupting_conversation_activity!(call, conversation)
    previous_last_activity_at = conversation.last_activity_at
    previous_waiting_since = conversation.waiting_since

    message = Voice::CallMessageBuilder.new(call).perform!
    call.update!(message_id: message.id) if call.message_id != message.id

    return unless message.previously_new_record?
    return if previous_last_activity_at.blank? || message.created_at >= previous_last_activity_at

    # rubocop:disable Rails/SkipsModelValidations
    conversation.update_columns(last_activity_at: previous_last_activity_at, waiting_since: previous_waiting_since)
    # rubocop:enable Rails/SkipsModelValidations
  end

  # El webhook manda raw_digits ya limpio, pero el endpoint REST de historial (GET /v1/calls) lo
  # devuelve formateado con espacios ("+52 983 195 0040") — hay que normalizarlo antes de compararlo
  # contra Contact#phone_number, que se guarda sin espacios.
  def raw_digits
    data[:raw_digits].to_s.gsub(/\s+/, '')
  end

  def aircall_call_id
    data[:id].to_s
  end

  # Una cuenta puede tener varias líneas de Aircall dadas de alta (una por número de
  # WhatsApp/SMS — ver feature_whatsapp_multi_number), cada una mapeada 1:1 a un inbox distinto de
  # Chatwoot. Antes se tomaba la conversación más antigua del contacto sin importar el inbox, así
  # que un contacto con historial en varios números terminaba con las llamadas de un número
  # colgadas de la conversación de otro — o de plano perdidas si esa conversación no existía en el
  # inbox de la línea que sonó. Aircall manda en cada call object un `number` (la línea que
  # participó, developers.aircall.io/api-references) que usamos para ubicar el inbox correcto.
  def find_conversation(contact)
    return contact.conversations.order(:created_at).first if matching_inbox.blank?

    contact.conversations.where(inbox: matching_inbox).order(:created_at).first
  end

  # nil cuando el payload no trae `number` (endpoints/tests viejos) o cuando ningún inbox de la
  # cuenta tiene ese número dado de alta como canal — en ambos casos #find_conversation cae al
  # comportamiento anterior (cualquier conversación del contacto), que sigue siendo correcto para
  # cuentas con una sola línea.
  def matching_inbox
    return @matching_inbox if defined?(@matching_inbox)

    @matching_inbox = find_matching_inbox
  end

  def find_matching_inbox
    digits = line_digits
    return if digits.blank?

    variants = phone_variants(digits)
    account.inboxes.includes(:channel).find { |inbox| variants.include?(inbox.channel.try(:phone_number)) }
  end

  def line_digits
    number = data[:number]
    return unless number.is_a?(Hash)

    number[:digits].to_s.gsub(/\s+/, '').presence
  end

  def find_contact
    account.contacts.where(phone_number: phone_variants).first || find_contact_by_local_number
  end

  # Some contacts get created with an incomplete phone_number missing the country code — e.g.
  # Click-to-WhatsApp ad leads, where the identifier Meta sends occasionally comes without it.
  # Aircall always sends the full number with country code, so falling back to a match on just
  # the last 10 digits (the local Mexican number) catches those without needing the DB record
  # fixed first — the call would otherwise be silently dropped (see #find_contact).
  def find_contact_by_local_number
    local_number = raw_digits.last(LOCAL_NUMBER_LENGTH)
    return if local_number.length < LOCAL_NUMBER_LENGTH

    account.contacts.where('phone_number LIKE ?', "%#{local_number}").first
  end

  def phone_variants(digits = raw_digits)
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
