# Reemplaza al correo que antes mandaba el flujo de Zoho Creator al terminar el botón
# crearCotizacionYEnviar — ahora Quotes::NotifyOwnerJob dispara esto justo después de que una
# cotización se genera exitosamente por primera vez (no en cada edición/recálculo posterior).
class QuoteMailer < ApplicationMailer
  def notify_owner(quote, to:)
    return unless smtp_config_set_or_development?
    return if to.blank?

    @quote = quote
    attach_pdf

    send_mail_with_liquid(to: to, subject: subject_for(quote))
  end

  private

  def subject_for(quote)
    "Cotización generada — #{quote.nombre} · #{quote.lote}".squish
  end

  def attach_pdf
    return unless @quote.pdf.attached?

    filename = "#{"cotizacion-#{@quote.lote.presence || @quote.id}".parameterize}.pdf"
    attachments[filename] = { mime_type: 'application/pdf', content: @quote.pdf.download }
  end

  def liquid_locals
    super.merge(
      'nombre' => @quote.nombre,
      'lote' => @quote.lote,
      'desarrollo' => @quote.desarrollo,
      'precio_total' => @quote.precio_total,
      'quote_url' => quote_url
    )
  end

  def quote_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{@quote.account_id}/quotes/#{@quote.id}"
  end
end
