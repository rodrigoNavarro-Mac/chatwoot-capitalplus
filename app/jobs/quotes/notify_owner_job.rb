# Reemplaza al aviso automático que antes mandaba Zoho Creator al terminar el botón
# crearCotizacionYEnviar del Deal — corre en background porque resolver el dueño de una
# cotización generada desde Producto (sin Deal) puede requerir una llamada a Zoho CRM (ver
# Quotes::ResolveOwnerEmailService), y no debe bloquear ni fallar la generación de la cotización
# en sí. Se dispara una sola vez, justo tras la generación inicial exitosa (ver
# Quotes::CalculateAndAttachService) — nunca en ediciones/recálculos posteriores.
class Quotes::NotifyOwnerJob < ApplicationJob
  queue_as :mailers

  def perform(quote_id)
    quote = Quote.find_by(id: quote_id)
    return if quote.blank? || !quote.completed?

    email = Quotes::ResolveOwnerEmailService.call(quote: quote)
    return if email.blank?

    QuoteMailer.with(account: quote.account).notify_owner(quote, to: email).deliver_later
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: quote&.account).capture_exception
  end
end
