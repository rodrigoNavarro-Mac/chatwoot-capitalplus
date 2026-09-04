# Resuelve/crea el RevenueContact ancla de un RevenueLead o RevenueDeal, 100% aditivo: nunca
# escribe en `contacts` ni llama a Crm::Zoho::ContactFinderService (ver decisión de alcance del
# plan de Fase 1 — esa duplicación con ZohoCrmController#search_zoho_by_phone es deuda técnica
# aceptada, no resuelta aquí).
#
# Algoritmo (ver también el plan de Fase 1, sección "Estrategia de identidad"):
#   1. Reúne TODAS las señales de matching disponibles (id de Zoho, teléfono normalizado, email,
#      chatwoot_contact_id derivado) y busca un revenue_contacts existente por cada una.
#   2. 0 candidatos distintos -> crea uno nuevo, anclado a la señal con índice único más fuerte
#      disponible (protege contra condiciones de carrera vía find_or_create_by!).
#   3. 1 candidato -> lo actualiza SOLO en los campos que estaban en null; nunca sobrescribe un
#      valor no-nulo existente con uno distinto (eso se registra como conflicto field_mismatch).
#   4. >1 candidatos distintos -> nunca fusiona automáticamente. Elige un primario determinístico
#      (el de mayor prioridad en SIGNAL_PRIORITY) y registra RevenueIdentityConflict con los
#      candidatos descartados — deuda de revisión manual explícita.
#
# Deals de Zoho no traen teléfono/email propio en esta cuenta (solo Contact_Name como lookup) —
# para resolve_for_deal el camino confiable es reusar el revenue_contact_id ya resuelto del
# RevenueLead vinculado (best-effort, ver RevenueDeal#revenue_lead_id); si no hay lead vinculado,
# se cae a matching por zoho_contact_id únicamente.
class RevenueIntelligence::IdentityResolver
  # Orden de prioridad: qué señal gana cuando varias apuntan a revenue_contacts distintos, y qué
  # columna se usa como ancla al crear uno nuevo (solo las que tienen índice único califican).
  CREATE_KEY_PRIORITY = %i[zoho_lead_id zoho_contact_id normalized_phone chatwoot_contact_id].freeze

  Attributes = Struct.new(:raw_phone, :email, :zoho_lead_id, :zoho_contact_id, :zoho_deal_id, keyword_init: true)

  def initialize(account)
    @account = account
  end

  def resolve_for_lead(revenue_lead)
    payload = revenue_lead.raw_payload || {}
    attrs = Attributes.new(
      raw_phone: payload['Mobile'].presence || payload['Phone'].presence,
      email: payload['Email'].presence,
      zoho_lead_id: revenue_lead.zoho_lead_id,
      zoho_contact_id: nil,
      zoho_deal_id: nil
    )

    contact = resolve(attrs, source: 'revenue_lead', source_id: revenue_lead.id)
    revenue_lead.update!(revenue_contact_id: contact.id)
    contact
  end

  def resolve_for_deal(revenue_deal)
    linked_contact = revenue_deal.revenue_lead&.revenue_contact
    if linked_contact
      linked_contact.update!(last_seen_at: Time.current)
      revenue_deal.update!(revenue_contact_id: linked_contact.id)
      return linked_contact
    end

    payload = revenue_deal.raw_payload || {}
    attrs = Attributes.new(
      raw_phone: nil,
      email: nil,
      zoho_lead_id: nil,
      zoho_contact_id: payload.dig('Contact_Name', 'id'),
      zoho_deal_id: revenue_deal.zoho_deal_id
    )

    contact = resolve(attrs, source: 'revenue_deal', source_id: revenue_deal.id)
    revenue_deal.update!(revenue_contact_id: contact.id)
    contact
  end

  private

  attr_reader :account

  def resolve(attrs, source:, source_id:)
    normalized_phone = normalize_phone(attrs.raw_phone)
    candidates = find_candidates(attrs, normalized_phone)

    case candidates.size
    when 0
      create_contact(attrs, normalized_phone, source: source, source_id: source_id)
    when 1
      merge_into(candidates.first.last, attrs, normalized_phone, source: source, source_id: source_id)
    else
      resolve_conflict(candidates, attrs, normalized_phone, source: source, source_id: source_id)
    end
  end

  # Devuelve pares [señal, RevenueContact] en orden de prioridad, deduplicados por contacto —
  # el primer elemento es siempre el candidato de mayor prioridad si hay varios distintos.
  def find_candidates(attrs, normalized_phone)
    found = []
    add_candidate(found, :zoho_lead_id, attrs.zoho_lead_id) { |v| account.revenue_contacts.find_by(zoho_lead_id: v) }
    add_candidate(found, :zoho_contact_id, attrs.zoho_contact_id) { |v| account.revenue_contacts.find_by(zoho_contact_id: v) }
    add_phone_candidate(found, attrs.raw_phone, normalized_phone)
    add_candidate(found, :email, attrs.email) { |v| account.revenue_contacts.where('lower(email) = ?', v.downcase).first }
    add_chatwoot_candidate(found, normalized_phone, attrs.email)

    found.uniq { |(_signal, contact)| contact.id }
  end

  def add_candidate(found, signal, value)
    return if value.blank?

    contact = yield(value)
    found << [signal, contact] if contact
  end

  # Guardia extra sobre el match por normalized_phone: además de la igualdad E.164, exige que los
  # últimos 10 dígitos del raw_phone original coincidan — mitiga (no elimina) el riesgo de que la
  # región default :MX fuerce un número extranjero de 10 dígitos a un E.164 mexicano incorrecto.
  def add_phone_candidate(found, raw_phone, normalized_phone)
    return if normalized_phone.blank?

    contact = account.revenue_contacts.find_by(normalized_phone: normalized_phone)
    return unless contact
    return unless last_ten_digits_match?(raw_phone, contact.raw_phone)

    found << [:normalized_phone, contact]
  end

  def last_ten_digits_match?(raw_a, raw_b)
    digits_a = raw_a.to_s.gsub(/\D/, '').last(10)
    digits_b = raw_b.to_s.gsub(/\D/, '').last(10)
    digits_a.present? && digits_a == digits_b
  end

  def add_chatwoot_candidate(found, normalized_phone, email)
    chatwoot_contact = find_chatwoot_contact(normalized_phone, email)
    return unless chatwoot_contact

    contact = account.revenue_contacts.find_by(chatwoot_contact_id: chatwoot_contact.id)
    found << [:chatwoot_contact_id, contact] if contact
  end

  # Solo lectura hacia `contacts` — nunca se escribe ahí desde este resolver. Compara contra
  # `normalized_phone` (E.164), NO raw_phone: Contact#phone_number valida un regex E.164 estricto
  # (\A\+[1-9]\d{1,14}\z), así que prácticamente todo teléfono real en `contacts` ya está en ese
  # formato — comparar contra el raw (formato libre de Zoho) casi nunca matchearía.
  def find_chatwoot_contact(normalized_phone, email)
    return nil if normalized_phone.blank? && email.blank?

    scope = account.contacts
    scope.find_by(phone_number: normalized_phone) || (email.present? ? scope.where('lower(email) = ?', email.downcase).first : nil)
  end

  def create_contact(attrs, normalized_phone, source:, source_id:)
    chatwoot_contact = find_chatwoot_contact(normalized_phone, attrs.email)
    now = Time.current
    full_attrs = {
      normalized_phone: normalized_phone, raw_phone: attrs.raw_phone, email: attrs.email,
      chatwoot_contact_id: chatwoot_contact&.id, zoho_lead_id: attrs.zoho_lead_id,
      zoho_contact_id: attrs.zoho_contact_id, zoho_deal_id: attrs.zoho_deal_id,
      first_seen_at: now, last_seen_at: now
    }

    key = strongest_create_key(attrs, normalized_phone, chatwoot_contact&.id)
    # Sin ninguna señal con índice único disponible (ej. deal sin Contact_Name resuelto y sin
    # lead vinculado) — se crea sin ancla de idempotencia; límite conocido y aceptado del MVP
    # (ver riesgos del plan de Fase 1), un reintento en esa condición extrema podría duplicar.
    return account.revenue_contacts.create!(full_attrs) if key.nil?

    key_column, key_value = key
    contact = account.revenue_contacts.find_or_create_by!(key_column => key_value) do |c|
      c.assign_attributes(full_attrs)
    end

    # Otro proceso ganó la carrera entre el chequeo de candidatos y este create! — el contacto ya
    # existía con datos propios, se trata como un match normal en vez de asumir que se creó.
    contact = merge_into(contact, attrs, normalized_phone, source: source, source_id: source_id) unless contact.previously_new_record?
    contact
  end

  def strongest_create_key(attrs, normalized_phone, chatwoot_contact_id)
    values = {
      zoho_lead_id: attrs.zoho_lead_id, zoho_contact_id: attrs.zoho_contact_id,
      normalized_phone: normalized_phone, chatwoot_contact_id: chatwoot_contact_id
    }
    CREATE_KEY_PRIORITY.each do |key|
      return [key, values[key]] if values[key].present?
    end
    nil
  end

  def merge_into(contact, attrs, normalized_phone, source:, source_id:)
    detect_field_mismatch(contact, attrs, source: source, source_id: source_id)
    contact.update!(merge_updates(contact, attrs, normalized_phone))
    contact
  end

  def merge_updates(contact, attrs, normalized_phone)
    chatwoot_contact = find_chatwoot_contact(normalized_phone, attrs.email)
    updates = { last_seen_at: Time.current }
    updates[:raw_phone] = attrs.raw_phone if fillable?(contact.raw_phone, attrs.raw_phone)
    updates[:email] = attrs.email if fillable?(contact.email, attrs.email)
    # zoho_deal_id es solo "deal más reciente" de conveniencia (ver comentario de la migración) —
    # se sobrescribe libremente, no es una señal de identidad ni dispara field_mismatch.
    updates[:zoho_deal_id] = attrs.zoho_deal_id if attrs.zoho_deal_id.present?

    updates.merge(unique_updates(contact, normalized_phone: normalized_phone, zoho_lead_id: attrs.zoho_lead_id,
                                          zoho_contact_id: attrs.zoho_contact_id, chatwoot_contact_id: chatwoot_contact&.id))
  end

  def fillable?(current, incoming)
    current.blank? && incoming.present?
  end

  # Igual que fillable?, pero para columnas con índice único: además de estar vacía, exige que
  # NINGÚN OTRO revenue_contacts ya tenga ese valor — necesario en la resolución de conflictos
  # (resolve_conflict), donde el primario puede tener la columna en null mientras el candidato
  # descartado ya la tiene ocupada. Llenarla ahí violaría el índice único y, peor, le robaría al
  # candidato descartado una señal que en realidad es suya.
  def unique_updates(contact, candidates)
    candidates.each_with_object({}) do |(column, incoming), updates|
      next unless fillable?(contact[column], incoming)
      next if account.revenue_contacts.where(column => incoming).where.not(id: contact.id).exists?

      updates[column] = incoming
    end
  end

  def detect_field_mismatch(contact, attrs, source:, source_id:)
    return unless field_mismatch?(contact, attrs)

    log_conflict('field_mismatch', [contact.id], attrs, source: source, source_id: source_id)
  end

  def field_mismatch?(contact, attrs)
    differs?(contact.zoho_lead_id, attrs.zoho_lead_id) ||
      differs?(contact.zoho_contact_id, attrs.zoho_contact_id) ||
      emails_differ?(contact.email, attrs.email)
  end

  def differs?(current, incoming)
    current.present? && incoming.present? && current != incoming
  end

  def emails_differ?(current, incoming)
    current.present? && incoming.present? && !current.casecmp?(incoming)
  end

  def resolve_conflict(candidates, attrs, normalized_phone, source:, source_id:)
    primary = candidates.first.last
    other_ids = candidates[1..].map { |(_signal, contact)| contact.id }
    log_conflict('multiple_candidates', [primary.id, *other_ids], attrs, source: source, source_id: source_id)
    merge_into(primary, attrs, normalized_phone, source: source, source_id: source_id)
  end

  def log_conflict(conflict_type, candidate_ids, attrs, source:, source_id:)
    account.revenue_identity_conflicts.create!(
      conflict_type: conflict_type,
      match_key: normalize_phone(attrs.raw_phone) || attrs.email,
      candidate_ids: candidate_ids,
      source: source,
      raw_context: {
        source_id: source_id, raw_phone: attrs.raw_phone, email: attrs.email,
        zoho_lead_id: attrs.zoho_lead_id, zoho_contact_id: attrs.zoho_contact_id, zoho_deal_id: attrs.zoho_deal_id
      }
    )
  end

  def normalize_phone(raw_phone)
    return nil if raw_phone.blank?

    parsed = TelephoneNumber.parse(raw_phone, 'MX')
    parsed.valid? ? parsed.e164_number : nil
  rescue StandardError
    nil
  end
end
