# Punto de entrada único para generar una Quote a partir de un deal_id de Zoho — tanto el webhook
# que Zoho puede llamar (Webhooks::ZohoCrmController#generate_quote) como el botón dentro de
# Chatwoot (Api::V1::Accounts::Integrations::ZohoCrmController#generate_quote) terminan llamando a
# este mismo servicio, para no duplicar la orquestación en dos controllers.
class Quotes::GenerateFromZohoDealService
  class DealNotFoundError < StandardError; end

  # Sin especificar `fields`, GET Deals/{id} no garantiza traer los campos custom de cotización
  # (ver el comentario de Crm::Zoho::Api::DealsClient#search_by_criteria sobre este mismo problema).
  REQUIRED_ZOHO_FIELDS = %w[
    Deal_Name Owner Desarollo Fecha_de_entrega Plazos Enganche Interes Superficie
    Precio_por_m2 Meses_sin_intereses Descuento Color Stage
  ].freeze

  def self.call(...)
    new(...).call
  end

  def initialize(account:, zoho_deal_id:, trigger_source:, contact: nil, generated_by: nil)
    @account = account
    @zoho_deal_id = zoho_deal_id
    @trigger_source = trigger_source
    @contact = contact
    @generated_by = generated_by
  end

  # Deja siempre un Quote persistido: 'completed' con el PDF adjunto, o 'failed' con error_message.
  # Solo deja de crear el registro si zoho_deal_id/trigger_source son inválidos (error del llamador,
  # no de la generación en sí) — eso se propaga como ActiveRecord::RecordInvalid al caller.
  def call
    @quote = create_pending_quote
    generate!
    @quote
  end

  private

  attr_reader :account, :zoho_deal_id, :trigger_source, :contact, :generated_by, :quote

  def create_pending_quote
    account.quotes.create!(
      source_type: 'deal',
      zoho_deal_id: zoho_deal_id,
      trigger_source: trigger_source,
      contact: contact || resolve_contact,
      generated_by: generated_by,
      status: 'pending'
    )
  end

  # El webhook de Zoho solo manda el deal_id — el contacto se resuelve por el mismo mecanismo que
  # ya usa Crm::Zoho::DealsSyncJob para cachear el link (additional_attributes.external.zoho_deal_id,
  # ver también app/builders/v2/reports/sales_funnel_deal_activity.rb). Cuando el trigger es el
  # botón de Chatwoot, el contacto ya viene explícito y no se ejecuta esta query.
  def resolve_contact
    return nil if zoho_deal_id.blank?

    account.contacts
           .where("additional_attributes -> 'external' ->> 'zoho_deal_id' = ?", zoho_deal_id)
           .first
  end

  def generate!
    payload = fetch_deal_payload
    raise DealNotFoundError, 'No se encontró el trato en Zoho CRM.' if payload.blank?

    Quotes::CalculateAndAttachService.call(quote: quote, payload: payload)
  rescue DealNotFoundError => e
    quote.update!(status: 'failed', error_message: e.message)
  end

  def fetch_deal_payload
    hook = account.hooks.find_by(app_id: 'zoho_crm', status: 'enabled')
    raise DealNotFoundError, 'Zoho CRM no está conectado en esta cuenta.' if hook.blank?

    Crm::Zoho::Api::DealsClient.new(hook).find(zoho_deal_id, fields: REQUIRED_ZOHO_FIELDS)
  end
end
