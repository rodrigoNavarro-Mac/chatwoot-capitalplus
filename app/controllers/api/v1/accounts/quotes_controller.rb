class Api::V1::Accounts::QuotesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_quote, only: [:show, :update, :pdf]

  def index
    @quotes = Current.account.quotes.filter_by_contact_id(params[:contact_id]).recent_first.limit(50)
  end

  def show; end

  # Autocomplete del módulo Products de Zoho CRM para el formulario "Generar cotización" — se
  # filtra primero por Desarrollo (Pick List) y opcionalmente por nombre de lote dentro de ese
  # desarrollo. Devuelve el registro completo de Zoho tal cual, el frontend intenta mapear las
  # llaves conocidas y el usuario puede corregir cualquier campo antes de generar.
  def products
    hook = Current.account.hooks.find_by(app_id: 'zoho_crm', status: 'enabled')
    return render json: [] if hook.blank?

    render json: Crm::Zoho::Api::ProductsClient.new(hook).search(word: params[:q], desarrollo: params[:desarrollo])
  end

  # Valores del Pick List "Desarrollo" de Products, para el selector que se muestra antes de
  # buscar el lote.
  def developments
    hook = Current.account.hooks.find_by(app_id: 'zoho_crm', status: 'enabled')
    return render json: [] if hook.blank?

    render json: Crm::Zoho::Api::ProductsClient.new(hook).desarrollos
  end

  # Genera una cotización nueva a partir de un Producto de Zoho (no de un Deal) — `fields` es el
  # estado completo del formulario, ya con lo que el usuario haya editado sobre los datos que
  # trajo el Producto. Ver Quotes::GenerateFromProductService.
  def create
    return render json: { error: 'zoho_product_id_required' }, status: :unprocessable_entity if params[:zoho_product_id].blank?

    @quote = Quotes::GenerateFromProductService.call(
      account: Current.account,
      zoho_product_id: params[:zoho_product_id],
      fields: quote_fields_params,
      contact: fetch_contact,
      generated_by: current_user
    )
    render :show
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Recalcula y regenera el PDF de una cotización existente con los campos editados desde el
  # detalle — los campos no enviados conservan su último valor (edición parcial).
  def update
    payload = Quotes::PayloadBuilder.build(quote_fields_with_current_defaults)
    Quotes::CalculateAndAttachService.call(quote: @quote, payload: payload)
    render :show
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

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

  def fetch_contact
    return nil if params[:contact_id].blank?

    Current.account.contacts.find_by(id: params[:contact_id])
  end

  def quote_fields_params
    params.permit(
      :nombre, :lote, :desarrollo, :color, :superficie, :precio_m2, :plazos,
      :enganche, :interes, :meses_sin_intereses, :descuento, :fecha_entrega
    ).to_h.symbolize_keys
  end

  # El formulario de edición manda solo lo que el usuario tocó — lo demás cae al valor actual de
  # la cotización (o, para `descuento`/`color`, al valor crudo original guardado en
  # `deal_snapshot`, ya que `descuento_aplicado` es el monto ya calculado, no el % o monto fijo que
  # capturó el usuario).
  CURRENT_VALUE_FALLBACKS = {
    nombre: :nombre, lote: :lote, desarrollo: :desarrollo, superficie: :superficie,
    precio_m2: :precio_m2, plazos: :plazos, enganche: :enganche_pct, interes: :interes_pct,
    meses_sin_intereses: :meses_sin_intereses, fecha_entrega: :fecha_entrega
  }.freeze
  SNAPSHOT_VALUE_FALLBACKS = { color: 'Color', descuento: 'Descuento' }.freeze

  def quote_fields_with_current_defaults
    submitted = quote_fields_params
    snapshot = @quote.deal_snapshot || {}

    fallbacks = CURRENT_VALUE_FALLBACKS.transform_values { |attr| @quote.public_send(attr) }
                                       .merge(SNAPSHOT_VALUE_FALLBACKS.transform_values { |key| snapshot[key] })

    fallbacks.merge(submitted) { |_key, fallback, given| given.presence || fallback }
  end
end
