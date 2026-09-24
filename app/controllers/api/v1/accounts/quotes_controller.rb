class Api::V1::Accounts::QuotesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_quote, only: [:show, :update, :pdf, :amortization_pdf]

  # Sin el permiso custom 'quote_sensitive_fields_manage' (o ser administrador), estos tres campos
  # quedan bloqueados server-side sin importar qué mande el request — el frontend también los
  # deshabilita (QuoteFieldsForm.vue) pero eso es solo UX, la fuente de verdad es este check.
  SENSITIVE_FIELDS = %i[descuento interes meses_sin_intereses].freeze
  DEFAULT_INTERES = '8'.freeze

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

    fields = lock_sensitive_fields(quote_fields_params, descuento: 0, interes: DEFAULT_INTERES, meses_sin_intereses: 0)
    @quote = Quotes::GenerateFromProductService.call(
      account: Current.account,
      zoho_product_id: params[:zoho_product_id],
      fields: fields,
      contact: fetch_contact,
      generated_by: current_user
    )
    render :show
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Recalcula y regenera el PDF de una cotización existente con los campos editados desde el
  # detalle — los campos no enviados conservan su último valor (edición parcial). Sin el permiso
  # de campos sensibles, descuento/interés/MSI se fuerzan a su valor actual sin importar qué se
  # haya mandado (edición parcial "de mentiras" para esos tres campos específicamente).
  def update
    fields = lock_sensitive_fields(
      quote_fields_with_current_defaults,
      descuento: @quote.deal_snapshot['Descuento'], interes: @quote.interes_pct, meses_sin_intereses: @quote.meses_sin_intereses
    )
    payload = Quotes::PayloadBuilder.build(fields)
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

  # Tabla de amortización completa (interés/capital/saldo por periodo), con el mismo estilo Fuego
  # que el PDF simple — se genera al vuelo en cada descarga (no se guarda, ya que sale directo de
  # `quote.schedule`) y puede ocupar varias páginas a diferencia del PDF que se le entrega al
  # cliente.
  def amortization_pdf
    html = Quotes::HtmlRendererService.new(@quote).render_amortization
    pdf_bytes = Quotes::PdfGeneratorService.new(html).generate
    send_data pdf_bytes,
              filename: "#{"amortizacion-#{@quote.lote.presence || @quote.id}".parameterize}.pdf",
              type: 'application/pdf',
              disposition: 'attachment'
  rescue Quotes::PdfGeneratorService::ConversionError => e
    render json: { error: e.message }, status: :unprocessable_entity
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

  def can_manage_sensitive_fields?
    Current.account_user.administrator? || Current.account_user.custom_role&.permissions&.include?('quote_sensitive_fields_manage')
  end

  # `locked_values` gana sobre lo que haya en `fields` para SENSITIVE_FIELDS cuando el usuario no
  # tiene el permiso — no basta con quitar la llave (interes es obligatorio para calcular un plan
  # financiado), hay que forzar un valor válido.
  def lock_sensitive_fields(fields, locked_values)
    return fields if can_manage_sensitive_fields?

    fields.merge(locked_values.slice(*SENSITIVE_FIELDS))
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
