# Puebla revenue_leads.first_human_contact_at/first_human_contact_channel/
# first_human_response_seconds/first_human_response_business_seconds (sección 2 del brief de
# Marketing) -- SOLO a partir de interacción HUMANA real, nunca automática:
#
#   - WhatsApp: Message#human_response? (app/models/message.rb) ya excluye mensajes con
#     automation_rule_id, campaign_id, y bots (AgentBot/Captain::Assistant) -- no se reimplementa
#     esa lógica aquí.
#   - Llamada: Call#status == 'completed' Y (direction == 'outgoing' O accepted_by_agent_id
#     presente) -- explícitamente NUNCA buzón/no contestada/rechazada (confirmado con el usuario:
#     "que sea desde chatwoot por mensaje de setter o llamada real del setter no buzon").
#
# Cobertura limitada por diseño: solo aplica a leads con RevenueContact#chatwoot_contact_id
# resuelto (identidad ligada a un Contact real de Chatwoot) -- el resto queda con
# first_human_contact_at nil para siempre y se muestra explícitamente como "sin dato" en el
# builder (V2::Reports::RevenueIntelligenceBuilder#marketing_sla), nunca se imputa un valor. Ver
# sesión previa: solo ~17.5% de los leads de esta cuenta tienen identidad resuelta en Chatwoot, la
# mayoría del contacto real es telefónico fuera de este sistema.
#
# También puebla first_call_attempt_at/first_call_attempt_seconds/first_call_attempt_business_seconds
# -- "tiempo hasta marcar" (pedido del equipo de marketing, sesión 2026-09-23), un concepto
# distinto: cuenta CUALQUIER llamada saliente sin importar si conectó o fue a buzón, ver
# process_call_attempt.
#
# Idempotente y sin cursor: cada campo se procesa con su propio scope "todavía nil" -- una vez
# encontrado, ya no cambia (es un hecho histórico), así que no hace falta recalcular leads ya
# resueltos en corridas futuras.
class RevenueIntelligence::CalculateSetterResponseTimeJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(account_id = nil)
    hooks = Integrations::Hook.enabled.where(app_id: 'zoho_crm')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      process_account(hook.account)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::CalculateSetterResponseTimeJob] account=#{hook.account_id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: hook.account).capture_exception
    end
  end

  private

  def process_account(account)
    eligible_leads(account).where(first_human_contact_at: nil).find_each { |lead| process_lead(lead) }
    # Scope propio (no first_human_contact_at: nil) -- un lead cuyo contacto real ya se resolvió
    # en una corrida anterior nunca vuelve a pasar por el where de arriba, pero puede seguir sin
    # first_call_attempt_at si nunca hubo un intento de llamada hasta ahora, o si este campo se
    # agregó después de que ese lead ya quedó resuelto.
    eligible_leads(account).where(first_call_attempt_at: nil).find_each { |lead| process_call_attempt(lead) }
  end

  def eligible_leads(account)
    account.revenue_leads.where.not(revenue_contact_id: nil).where.not(created_at_source: nil)
           .joins(:revenue_contact).where.not(revenue_contacts: { chatwoot_contact_id: nil })
  end

  def process_lead(lead)
    contact_id = lead.revenue_contact.chatwoot_contact_id
    candidates = [earliest_human_message_candidate(contact_id), earliest_real_call_candidate(contact_id)].compact
    return if candidates.empty?

    contact_at, channel, inbox = candidates.min_by { |candidate| candidate[0] }
    persist_response_time(lead, contact_at, channel, inbox)
  end

  def earliest_human_message_candidate(contact_id)
    messages = Message.joins(:conversation).where(conversations: { contact_id: contact_id })
                      .outgoing.where(private: false).order(created_at: :asc).includes(conversation: :inbox)
    human_message = messages.find(&:human_response?)
    return nil if human_message.blank?

    [human_message.created_at, 'whatsapp_message', human_message.conversation.inbox]
  end

  def earliest_real_call_candidate(contact_id)
    call = Call.where(contact_id: contact_id, status: 'completed')
               .where('direction = :outgoing OR accepted_by_agent_id IS NOT NULL', outgoing: Call.directions['outgoing'])
               .order(started_at: :asc).first
    return nil if call.blank? || call.started_at.blank?

    [call.started_at, 'call', call.inbox]
  end

  def persist_response_time(lead, contact_at, channel, inbox)
    clock_seconds, business_seconds = elapsed_seconds(lead, contact_at, inbox)
    lead.update!(first_human_contact_at: contact_at, first_human_contact_channel: channel,
                 first_human_response_seconds: clock_seconds, first_human_response_business_seconds: business_seconds)
  end

  # "Tiempo hasta marcar" (pedido explícito del equipo de marketing, sesión 2026-09-23):
  # DELIBERADAMENTE distinto de earliest_real_call_candidate -- cuenta cualquier llamada SALIENTE
  # del setter sin importar status (completed/no_answer/failed/voicemail), porque la pregunta de
  # negocio es "¿qué tan rápido INTENTA el setter el contacto?", no si logró conectar. Nunca cuenta
  # llamadas entrantes (esas las inicia el lead, no miden la velocidad del setter).
  def process_call_attempt(lead)
    contact_id = lead.revenue_contact.chatwoot_contact_id
    call = Call.where(contact_id: contact_id, direction: Call.directions['outgoing']).order(started_at: :asc).first
    return if call.blank? || call.started_at.blank?

    clock_seconds, business_seconds = elapsed_seconds(lead, call.started_at, call.inbox)
    lead.update!(first_call_attempt_at: call.started_at, first_call_attempt_seconds: clock_seconds,
                 first_call_attempt_business_seconds: business_seconds)
  end

  def elapsed_seconds(lead, event_at, inbox)
    clock_seconds = [(event_at - lead.created_at_source).round, 0].max
    business_seconds = RevenueIntelligence::BusinessElapsedTimeCalculator.new(inbox).elapsed_seconds(lead.created_at_source, event_at)
    [clock_seconds, business_seconds]
  end
end
