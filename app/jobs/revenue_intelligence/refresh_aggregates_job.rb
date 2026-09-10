# Agrega revenue_events/revenue_call_features/revenue_stage_events/call_analyses en revenue_rollups
# (patrón dimensional genérico — ver el modelo y el plan de Fase 3). Todas las filas se escriben
# con upsert_all + ON CONFLICT (count/sum_value se ACUMULAN, nunca se reemplazan), mismo patrón
# que ReportingEvents::RollupService — así que este job puede correr sobre una ventana
# estrictamente incremental sin recalcular el histórico completo cada vez.
#
# Convención metric = event_type verbatim para la dimensión "funnel" (evita una capa de traducción
# de nombres innecesaria). Ver comentario de cada método `*_rows` para el resto de convenciones.
class RevenueIntelligence::RefreshAggregatesJob < ApplicationJob
  queue_as :scheduled_jobs

  # Orden = orden real del funnel (Leads -> Contactados -> Calificados -> Deals -> Citas -> Visitas
  # -> Apartados -> Ventas/Perdidos) — la UI (Fase 6) depende de este orden para dibujar el embudo,
  # no lo reordenar sin revisar RevenueIntelligenceReport.vue.
  FUNNEL_EVENT_TYPES = %w[lead_created lead_contacted lead_qualified deal_created appointment_created visit_effective reserved closed_won
                          closed_lost].freeze
  AGENT_EVENT_TYPES = %w[call_started call_answered call_missed].freeze
  SCORE_BANDS = { (0..39) => '0-39', (40..69) => '40-69', (70..100) => '70-100' }.freeze

  # Zoho devuelve todos sus timestamps en -06:00 para esta cuenta (confirmado contra decenas de
  # leads de meses distintos, sin variación estacional -- no es horario de verano, es el timezone
  # fijo configurado en el propio org de Zoho). La app no tiene Time.zone configurado (default
  # UTC), así que sin esto un lead creado a las 22:00 hora real del 31 de julio se bucketeaba como
  # "1 de agosto" -- confirmado en producción: 239 leads calculados vs. 231 reales en Zoho para
  # agosto 2026.
  LOCAL_TIMEZONE = 'America/Mexico_City'.freeze

  def perform(account_id = nil)
    hooks = Integrations::Hook.enabled.where(app_id: 'zoho_crm')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      build_for_account(hook.account)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::RefreshAggregatesJob] account=#{hook.account_id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: hook.account).capture_exception
    end
  end

  private

  def build_for_account(account)
    cursor_service = RevenueIntelligence::SyncCursorService.new(account, 'rollups')
    since = cursor_service.since
    until_at = Time.current

    upsert_rows(build_rows(account, since, until_at))

    cursor_service.advance!(until_at)
  rescue StandardError => e
    cursor_service&.record_error!(e.message)
    raise
  end

  def build_rows(account, since, until_at)
    lookups = desarrollo_lookups(account)
    converted_ids = converted_lead_ids(account)

    funnel_rows(account, since, until_at, lookups) + agent_rows(account, since, until_at, lookups) +
      agent_call_quality_rows(account, since, until_at, lookups) + campaign_rows(account, since, until_at, converted_ids) +
      source_rows(account, since, until_at, converted_ids) + pipeline_stage_rows(account, since, until_at, lookups) +
      call_conversion_rows(account, since, until_at, lookups) + objection_conversion_rows(account, since, until_at, lookups)
  end

  # { zoho_lead_id => desarrollo }, { zoho_deal_id => desarrollo } — construidos UNA vez por
  # corrida y compartidos entre todos los *_rows que necesitan atribuir un desarrollo a un evento
  # que solo trae zoho_lead_id/zoho_deal_id (no la columna desarrollo directo). campaign_rows es la
  # única excepción: lee revenue_leads/revenue_deals directo, así que puede pluckear :desarrollo
  # sin pasar por aquí.
  def desarrollo_lookups(account)
    {
      lead: account.revenue_leads.pluck(:zoho_lead_id, :desarrollo).to_h,
      deal: account.revenue_deals.pluck(:zoho_deal_id, :desarrollo).to_h
    }
  end

  # Prioridad deal > lead > '_all', igual que funnel_rows ya establecía — un deal puede tener su
  # propio desarrollo distinto al del lead que lo originó (ver DealMapper), y no todo evento trae
  # ambos ids.
  def resolve_desarrollo(lookups, zoho_lead_id: nil, zoho_deal_id: nil)
    lookups[:deal][zoho_deal_id] || lookups[:lead][zoho_lead_id] || '_all'
  end

  # IDs de revenue_leads que YA tienen un revenue_deal asociado (best-effort vía
  # revenue_deals.revenue_lead_id, ver Fase 1) -- para la métrica 'lead_converted' de
  # campaign/lead_source: cuántos de los leads CREADOS en el periodo ya se convirtieron a Deal.
  # Sin esto, un cliente que compara "Leads" de esta pantalla contra un reporte de Zoho que excluye
  # convertidos por default (comportamiento real confirmado de la API de Search/COQL de Zoho) ve un
  # número más alto aquí sin entender por qué -- confirmado como el origen real de una consulta en
  # producción (2026-09-10): 11 de 155 leads de una campaña ya estaban convertidos, y Zoho's propio
  # conteo (que excluye convertidos) mostraba 146.
  def converted_lead_ids(account)
    account.revenue_deals.where.not(revenue_lead_id: nil).distinct.pluck(:revenue_lead_id).to_set
  end

  def window(column, since, until_at)
    since ? { column => since...until_at } : { column => ..until_at }
  end

  def local_date(time)
    time.in_time_zone(LOCAL_TIMEZONE).to_date
  end

  # Postgres rechaza un upsert_all cuyo VALUES tenga dos filas que apunten al mismo índice único
  # ("ON CONFLICT DO UPDATE command cannot affect row a second time") — algo que pasa todo el
  # tiempo aquí (ej. dos leads del mismo desarrollo el mismo día). Por eso se pre-agrupan/suman
  # las filas por su clave de negocio ANTES de mandarlas a Postgres; el ON CONFLICT de abajo sigue
  # existiendo para acumular contra lo que ya quedó guardado de corridas anteriores.
  def upsert_rows(rows)
    return if rows.empty?

    merged = rows.each_with_object({}) do |row, acc|
      key = row.values_at(:account_id, :date, :dimension_type, :dimension_id, :metric, :desarrollo)
      if acc.key?(key)
        acc[key][:count] += row[:count]
        acc[key][:sum_value] += row[:sum_value]
      else
        acc[key] = row.dup
      end
    end

    now = Time.current
    # rubocop:disable Rails/SkipsModelValidations
    RevenueRollup.upsert_all(
      merged.values.map { |row| row.merge(created_at: now, updated_at: now) },
      unique_by: [:account_id, :date, :dimension_type, :dimension_id, :metric, :desarrollo],
      on_duplicate: Arel.sql('count = revenue_rollups.count + EXCLUDED.count, sum_value = revenue_rollups.sum_value + ' \
                             'EXCLUDED.sum_value, updated_at = EXCLUDED.updated_at')
    )
    # rubocop:enable Rails/SkipsModelValidations
  end

  # rubocop:disable Metrics/ParameterLists
  def row(account, date, dimension_type, dimension_id, metric, count: 1, sum_value: 0, desarrollo: '_all')
    { account_id: account.id, date: date, dimension_type: dimension_type, dimension_id: dimension_id.to_s, metric: metric,
      count: count, sum_value: sum_value, desarrollo: desarrollo }
  end
  # rubocop:enable Metrics/ParameterLists

  # dimension_id: desarrollo (heredado del lead o, si el evento es de un deal, del deal — ver
  # RevenueIntelligence::DealMapper sobre por qué el deal puede tener su propio desarrollo
  # distinto). metric = event_type verbatim.
  def funnel_rows(account, since, until_at, lookups)
    events = account.revenue_events.where(event_type: FUNNEL_EVENT_TYPES).where(window(:event_at, since, until_at))

    events.pluck(:event_type, :event_at, :zoho_lead_id, :zoho_deal_id).map do |event_type, event_at, zoho_lead_id, zoho_deal_id|
      desarrollo = resolve_desarrollo(lookups, zoho_lead_id: zoho_lead_id, zoho_deal_id: zoho_deal_id)
      row(account, local_date(event_at), 'funnel', desarrollo, event_type, desarrollo: desarrollo)
    end
  end

  # dimension_id: agent_id (Chatwoot User id) — solo actividad de llamadas, que es lo único que
  # revenue_events trae ligado a un User de Chatwoot (el owner de un Deal en Zoho vive en otro
  # espacio de ids, no se cruza aquí — ver riesgos del plan de Fase 3).
  def agent_rows(account, since, until_at, lookups)
    events = account.revenue_events.where(event_type: AGENT_EVENT_TYPES).where.not(agent_id: nil).where(window(:event_at, since, until_at))

    events.pluck(:event_type, :event_at, :agent_id, :zoho_lead_id, :zoho_deal_id).map do |event_type, event_at, agent_id, zoho_lead_id, zoho_deal_id|
      desarrollo = resolve_desarrollo(lookups, zoho_lead_id: zoho_lead_id, zoho_deal_id: zoho_deal_id)
      row(account, local_date(event_at), 'agent', agent_id, event_type, desarrollo: desarrollo)
    end
  end

  # dimension_id: agent_id, igual que agent_rows — pero la fuente es revenue_call_features (no
  # revenue_events), la única tabla que ya trae score/cta_used ligados a un agent_id real de
  # Chatwoot. metric 'calls_scored' = denominador para los promedios; 'score_sum' (sum_value) y
  # 'cta_used_count' (count) se dividen entre 'calls_scored' en el builder para avg_score/cta_rate
  # — mismo patrón sum_value/count ya usado en pipeline_stage_rows para promedios.
  def agent_call_quality_rows(account, since, until_at, lookups)
    features = account.revenue_call_features.where.not(agent_id: nil).where(window(:started_at, since, until_at))

    features.pluck(:agent_id, :started_at, :score_total, :cta_used,
                   :zoho_deal_id).flat_map do |agent_id, started_at, score_total, cta_used, zoho_deal_id|
      date = local_date(started_at)
      desarrollo = resolve_desarrollo(lookups, zoho_deal_id: zoho_deal_id)
      rows = [row(account, date, 'agent', agent_id, 'calls_scored', desarrollo: desarrollo)]
      rows << row(account, date, 'agent', agent_id, 'score_sum', count: 0, sum_value: score_total, desarrollo: desarrollo) if score_total.present?
      rows << row(account, date, 'agent', agent_id, 'cta_used_count', desarrollo: desarrollo) if cta_used
      rows
    end
  end

  # dimension_id: campaign_id (y, en paralelo, adset/advert — ver marketing_dimension_rows).
  # lead_created/lead_contacted desde revenue_leads directo (no vía eventos, el campaign_id no
  # viaja en el evento); lead_converted = de los leads CREADOS en el periodo, cuántos ya tienen un
  # revenue_deal asociado (ver converted_lead_ids) -- misma cohorte que lead_created, para que la
  # UI pueda anotar "X ya convertidos" junto al conteo de Leads; deal_created/closed_won heredados
  # del campaign_id del lead de origen del deal (best-effort, ver revenue_deals.revenue_lead_id en
  # Fase 1) — deal_created para saber qué campaña/adset/advert produce deals (no solo ventas
  # cerradas), closed_won para la venta en sí.
  def campaign_rows(account, since, until_at, converted_ids)
    campaign_lead_rows(account, since, until_at, :created_at_source, 'lead_created') +
      campaign_lead_rows(account, since, until_at, :first_contact_at, 'lead_contacted') +
      campaign_lead_rows(account, since, until_at, :created_at_source, 'lead_converted', converted_ids: converted_ids) +
      campaign_deal_rows(account, since, until_at, date_column: :created_at_source, metric: 'deal_created', won_only: false) +
      campaign_deal_rows(account, since, until_at, date_column: :updated_at, metric: 'closed_won', won_only: true)
  end

  # dimension_id: Lead_Source ("Facebook Ads"/"Google Ads"/etc., o 'Sin fuente') — bucket de
  # respaldo para el ~94% de leads sin campaign_id (confirmado contra Zoho: la atribución fina de
  # campaña solo existe desde el 10 de agosto de 2026 para esta cuenta). Sin esto, la pestaña de
  # Marketing solo mostraba la fracción con campaña y daba la impresión de que el marketing
  # "empezó" en esa fecha. Mismas métricas que campaign_rows, misma semántica.
  def source_rows(account, since, until_at, converted_ids)
    source_lead_rows(account, since, until_at, :created_at_source, 'lead_created') +
      source_lead_rows(account, since, until_at, :first_contact_at, 'lead_contacted') +
      source_lead_rows(account, since, until_at, :created_at_source, 'lead_converted', converted_ids: converted_ids) +
      source_deal_rows(account, since, until_at, date_column: :created_at_source, metric: 'deal_created', won_only: false) +
      source_deal_rows(account, since, until_at, date_column: :updated_at, metric: 'closed_won', won_only: true)
  end

  # rubocop:disable Metrics/ParameterLists
  def source_lead_rows(account, since, until_at, date_column, metric, converted_ids: nil)
    scope = account.revenue_leads.where(campaign_id: nil).where.not(date_column => nil).where(window(date_column, since, until_at))
    scope = scope.where(id: converted_ids.to_a) if converted_ids
    scope.pluck(:lead_source, :desarrollo, date_column)
         .map { |lead_source, desarrollo, date| source_row(account, local_date(date), lead_source, desarrollo, metric) }
  end
  # rubocop:enable Metrics/ParameterLists

  # rubocop:disable Metrics/ParameterLists
  def source_deal_rows(account, since, until_at, date_column:, metric:, won_only:)
    scope = account.revenue_deals.joins(:revenue_lead).where(revenue_leads: { campaign_id: nil })
    scope = scope.where(won: true) if won_only
    scope.where.not(date_column => nil).where(window(date_column, since, until_at))
         .pluck('revenue_leads.lead_source', 'revenue_deals.desarrollo', date_column)
         .map { |lead_source, desarrollo, date| source_row(account, local_date(date), lead_source, desarrollo, metric) }
  end
  # rubocop:enable Metrics/ParameterLists

  def source_row(account, date, lead_source, desarrollo, metric)
    row(account, date, 'lead_source', lead_source.presence || 'Sin fuente', metric, desarrollo: desarrollo || '_all')
  end

  # rubocop:disable Metrics/ParameterLists
  def campaign_lead_rows(account, since, until_at, date_column, metric, converted_ids: nil)
    scope = account.revenue_leads.where.not(campaign_id: nil).where.not(date_column => nil).where(window(date_column, since, until_at))
    scope = scope.where(id: converted_ids.to_a) if converted_ids
    scope.pluck(:campaign_id, :adset_id, :adset_name, :advert_id, :advert_name, :desarrollo, date_column)
         .flat_map { |cols| marketing_dimension_rows(account, local_date(cols.last), cols[0..5], metric) }
  end
  # rubocop:enable Metrics/ParameterLists

  # rubocop:disable Metrics/ParameterLists
  def campaign_deal_rows(account, since, until_at, date_column:, metric:, won_only:)
    scope = account.revenue_deals.joins(:revenue_lead).where.not(revenue_leads: { campaign_id: nil })
    scope = scope.where(won: true) if won_only
    scope.where.not(date_column => nil).where(window(date_column, since, until_at))
         .pluck('revenue_leads.campaign_id', 'revenue_leads.adset_id', 'revenue_leads.adset_name',
                'revenue_leads.advert_id', 'revenue_leads.advert_name', 'revenue_deals.desarrollo', date_column)
         .flat_map { |cols| marketing_dimension_rows(account, local_date(cols.last), cols[0..5], metric) }
  end
  # rubocop:enable Metrics/ParameterLists

  # Emite hasta 3 filas por lead/deal de marketing: 'campaign' (siempre, dimension_id = campaign_id
  # tal cual — SIN cambiar esta clave, ya tiene datos reales acumulados en producción desde Fase 3),
  # 'adset' (si el lead trae adset_id) y 'advert' (si además trae advert_id). dimension_id de
  # adset/advert es una clave compuesta "campaign_id::adset_id::nombre_o_id" (adset) /
  # "campaign_id::adset_id::advert_id::nombre_o_id" (advert) — ambos son dimensiones nuevas sin
  # datos previos, así que pueden llevar el nombre embebido: el builder solo lee revenue_rollups
  # (nunca revenue_leads), así que el nombre legible tiene que viajar dentro del propio
  # dimension_id, no resolverse aparte. desarrollo viene directo de la columna del lead/deal (no
  # hace falta el lookup compartido: campaign_rows ya lee revenue_leads/revenue_deals de por sí).
  def marketing_dimension_rows(account, date, ids, metric)
    campaign_id, adset_id, adset_name, advert_id, advert_name, desarrollo = ids
    desarrollo ||= '_all'
    rows = [row(account, date, 'campaign', campaign_id, metric, desarrollo: desarrollo)]
    return rows if adset_id.blank?

    rows << row(account, date, 'adset', "#{campaign_id}::#{adset_id}::#{adset_name.presence || adset_id}", metric, desarrollo: desarrollo)
    return rows if advert_id.blank?

    rows << row(account, date, 'advert', "#{campaign_id}::#{adset_id}::#{advert_id}::#{advert_name.presence || advert_id}", metric,
                desarrollo: desarrollo)
    rows
  end

  # dimension_id: stage. "entered" cuenta filas nuevas por fecha de entrada; "duration_seconds"
  # (sum_value) solo se agrega cuando la fila ya cerró (exited_at presente) — la fila abierta
  # actual no aporta duración todavía, se agregará en una corrida futura cuando cierre.
  def pipeline_stage_rows(account, since, until_at, lookups)
    entered = account.revenue_stage_events.where(window(:created_at, since, until_at)).pluck(:stage, :entered_at, :zoho_deal_id)
                     .map do |stage, entered_at, zoho_deal_id|
      row(account, local_date(entered_at), 'pipeline_stage', stage, 'entered', desarrollo: resolve_desarrollo(lookups, zoho_deal_id: zoho_deal_id))
    end

    closed = account.revenue_stage_events.where.not(exited_at: nil).where(window(:created_at, since, until_at))
                    .pluck(:stage, :exited_at, :duration_seconds, :zoho_deal_id)
                    .map do |stage, exited_at, duration_seconds, zoho_deal_id|
      desarrollo = resolve_desarrollo(lookups, zoho_deal_id: zoho_deal_id)
      row(account, local_date(exited_at), 'pipeline_stage', stage, 'duration_seconds', count: 1, sum_value: duration_seconds || 0,
                                                                                       desarrollo: desarrollo)
    end

    entered + closed
  end

  # dimension_id: clave compuesta "campo:valor" (cta_used:true/false, intent_level:<valor>,
  # score_band:<rango>). metric "calls" = denominador, "appointments_after" = numerador (¿hubo un
  # appointment_created de ese contacto después del inicio de la llamada?). Asociación, no
  # causalidad — ver riesgos del plan de Fase 3.
  def call_conversion_rows(account, since, until_at, lookups)
    features = account.revenue_call_features.where(window(:created_at, since, until_at))
    appointments = appointments_after_lookup(account)

    features.find_each.flat_map do |feature|
      converted = appointment_after?(appointments, feature.revenue_contact_id, feature.started_at)
      desarrollo = resolve_desarrollo(lookups, zoho_deal_id: feature.zoho_deal_id)
      call_conversion_dimensions(feature).flat_map do |dimension_id|
        conversion_pair(account, feature.started_at, 'call_conversion', dimension_id, converted, desarrollo)
      end
    end
  end

  def call_conversion_dimensions(feature)
    [
      "cta_used:#{feature.cta_used}",
      feature.intent_level.present? ? "intent_level:#{feature.intent_level}" : nil,
      feature.score_total.present? ? "score_band:#{score_band(feature.score_total)}" : nil
    ].compact
  end

  def score_band(score)
    SCORE_BANDS.find { |range, _label| range.cover?(score.to_i) }&.last || 'unknown'
  end

  # dimension_id: categoría de objeción (lee call_analyses.objections directo — no se aplanó a
  # revenue_call_features, que no tiene una fila por objeción individual).
  def objection_conversion_rows(account, since, until_at, lookups)
    contact_by_call = account.revenue_call_features.pluck(:call_id, :revenue_contact_id, :started_at, :zoho_deal_id)
                             .to_h { |call_id, contact_id, started_at, zoho_deal_id| [call_id, [contact_id, started_at, zoho_deal_id]] }
    appointments = appointments_after_lookup(account)

    CallAnalysis.where(account_id: account.id, status: 'completed').where(window(:analyzed_at, since, until_at)).find_each.flat_map do |analysis|
      contact_id, started_at, zoho_deal_id = contact_by_call[analysis.call_id]
      next [] unless contact_id

      converted = appointment_after?(appointments, contact_id, started_at)
      desarrollo = resolve_desarrollo(lookups, zoho_deal_id: zoho_deal_id)
      Array(analysis.objections).filter_map { |o| o['category'] }.flat_map do |category|
        conversion_pair(account, analysis.analyzed_at, 'objection_conversion', category, converted, desarrollo)
      end
    end
  end

  # rubocop:disable Metrics/ParameterLists
  def conversion_pair(account, date, dimension_type, dimension_id, converted, desarrollo)
    local = local_date(date)
    rows = [row(account, local, dimension_type, dimension_id, 'total', desarrollo: desarrollo)]
    rows << row(account, local, dimension_type, dimension_id, 'converted', desarrollo: desarrollo) if converted
    rows
  end
  # rubocop:enable Metrics/ParameterLists

  def appointments_after_lookup(account)
    account.revenue_events.where(event_type: 'appointment_created').where.not(revenue_contact_id: nil)
           .pluck(:revenue_contact_id, :event_at).group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
  end

  def appointment_after?(appointments, revenue_contact_id, after_time)
    return false if revenue_contact_id.blank? || after_time.blank?

    Array(appointments[revenue_contact_id]).any? { |event_at| event_at > after_time }
  end
end
