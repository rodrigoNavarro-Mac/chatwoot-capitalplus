class Api::V1::Accounts::QuotesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_quote, only: [:show, :pdf]

  def index
    @quotes = Current.account.quotes.filter_by_contact_id(params[:contact_id]).recent_first.limit(50)
  end

  def show; end

  def pdf
    return render json: { error: 'pdf_not_available' }, status: :not_found unless @quote.pdf.attached?

    send_data @quote.pdf.download,
              filename: "#{"cotizacion-#{@quote.lote.presence || @quote.id}".parameterize}.pdf",
              type: 'application/pdf',
              disposition: 'attachment'
  end

  private

  def check_authorization
    authorize(Quote)
  end

  def fetch_quote
    @quote = Current.account.quotes.find(params[:id])
  end
end
