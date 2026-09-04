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

    rows = funnel_rows(account, since, until_at) + agent_rows(account, since, until_at) +
           agent_call_quality_rows(account, since, until_at) + campaign_rows(account, since, until_at) +
           pipeline_stage_rows(account, since, until_at) + call_conversion_rows(account, since, until_at) +
           objection_conversion_rows(account, since, until_at)
    upsert_rows(rows)

    cursor_service.advance!(until_at)
  rescue StandardError => e
    cursor_service&.record_error!(e.message)
    raise
  end

  def window(column, since, until_at)
    since ? { column => since...until_at } : { column => ..until_at }
  end

  # Postgres rechaza un upsert_all cuyo VALUES tenga dos filas que apunten al mismo índice único
  # ("ON CONFLICT DO UPDATE command cannot affect row a second time") — algo que pasa todo el
  # tiempo aquí (ej. dos leads del mismo desarrollo el mismo día). Por eso se pre-agrupan/suman
  # las filas por su clave de negocio ANTES de mandarlas a Postgres; el ON CONFLICT de abajo sigue
  # existiendo para acumular contra lo que ya quedó guardado de corridas anteriores.
  def upsert_rows(rows)
    return if rows.empty?

    merged = rows.each_with_object({}) do |row, acc|
      key = row.values_at(:account_id, :date, :dimension_type, :dimension_id, :metric)
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
      unique_by: [:account_id, :date, :dimension_type, :dimension_id, :metric],
      on_duplicate: Arel.sql('count = revenue_rollups.count + EXCLUDED.count, sum_value = revenue_rollups.sum_value + ' \
                             'EXCLUDED.sum_value, updated_at = EXCLUDED.updated_at')
    )
    # rubocop:enable Rails/SkipsModelValidations
  end

  # rubocop:disable Metrics/ParameterLists
  def row(account, date, dimension_type, dimension_id, metric, count: 1, sum_value: 0)
    { account_id: account.id, date: date, dimension_type: dimension_type, dimension_id: dimension_id.to_s, metric: metric,
      count: count, sum_value: sum_value }
  end
  # rubocop:enable Metrics/ParameterLists

  # dimension_id: desarrollo (heredado del lead o, si el evento es de un deal, del deal — ver
  # RevenueIntelligence::DealMapper sobre por qué el deal puede tener su propio desarrollo
  # distinto). metric = event_type verbatim.
  def funnel_rows(account, since, until_at)
    events = account.revenue_events.where(event_type: FUNNEL_EVENT_TYPES).where(window(:event_at, since, until_at))
    lead_desarrollo = account.revenue_leads.pluck(:zoho_lead_id, :desarrollo).to_h
    deal_desarrollo = account.revenue_deals.pluck(:zoho_deal_id, :desarrollo).to_h

    events.pluck(:event_type, :event_at, :zoho_lead_id, :zoho_deal_id).map do |event_type, event_at, zoho_lead_id, zoho_deal_id|
      desarrollo = deal_desarrollo[zoho_deal_id] || lead_desarrollo[zoho_lead_id] || '_all'
      row(account, event_at.to_date, 'funnel', desarrollo, event_type)
    end
  end

  # dimension_id: agent_id (Chatwoot User id) — solo actividad de llamadas, que es lo único que
  # revenue_events trae ligado a un User de Chatwoot (el owner de un Deal en Zoho vive en otro
  # espacio de ids, no se cruza aquí — ver riesgos del plan de Fase 3).
  def agent_rows(account, since, until_at)
    events = account.revenue_events.where(event_type: AGENT_EVENT_TYPES).where.not(agent_id: nil).where(window(:event_at, since, until_at))

    events.pluck(:event_type, :event_at, :agent_id).map do |event_type, event_at, agent_id|
      row(account, event_at.to_date, 'agent', agent_id, event_type)
    end
  end

  # dimension_id: agent_id, igual que agent_rows — pero la fuente es revenue_call_features (no
  # revenue_events), la única tabla que ya trae score/cta_used ligados a un agent_id real de
  # Chatwoot. metric 'calls_scored' = denominador para los promedios; 'score_sum' (sum_value) y
  # 'cta_used_count' (count) se dividen entre 'calls_scored' en el builder para avg_score/cta_rate
  # — mismo patrón sum_value/count ya usado en pipeline_stage_rows para promedios.
  def agent_call_quality_rows(account, since, until_at)
    features = account.revenue_call_features.where.not(agent_id: nil).where(window(:started_at, since, until_at))

    features.pluck(:agent_id, :started_at, :score_total, :cta_used).flat_map do |agent_id, started_at, score_total, cta_used|
      date = started_at.to_date
      rows = [row(account, date, 'agent', agent_id, 'calls_scored')]
      rows << row(account, date, 'agent', agent_id, 'score_sum', count: 0, sum_value: score_total) if score_total.present?
      rows << row(account, date, 'agent', agent_id, 'cta_used_count') if cta_used
      rows
    end
  end

  # dimension_id: campaign_id (y, en paralelo, adset/advert — ver marketing_dimension_rows).
  # leads_created desde revenue_leads directo (no vía eventos, el campaign_id no viaja en el
  # evento); closed_won heredado del campaign_id del lead de origen del deal (best-effort, ver
  # revenue_deals.revenue_lead_id en Fase 1).
  def campaign_rows(account, since, until_at)
    lead_rows = account.revenue_leads.where.not(campaign_id: nil).where(window(:created_at_source, since, until_at))
                       .pluck(:campaign_id, :adset_id, :adset_name, :advert_id, :advert_name, :created_at_source)
                       .flat_map do |cols|
      marketing_dimension_rows(account, cols.last.to_date, cols[0..4], 'lead_created')
    end

    won_rows = account.revenue_deals.joins(:revenue_lead).where.not(revenue_leads: { campaign_id: nil })
                      .where(won: true).where(window(:updated_at, since, until_at))
                      .pluck('revenue_leads.campaign_id', 'revenue_leads.adset_id', 'revenue_leads.adset_name',
                             'revenue_leads.advert_id', 'revenue_leads.advert_name', :updated_at)
                      .flat_map do |cols|
      marketing_dimension_rows(account, cols.last.to_date, cols[0..4], 'closed_won')
    end

    lead_rows + won_rows
  end

  # Emite hasta 3 filas por lead/deal de marketing: 'campaign' (siempre, dimension_id = campaign_id
  # tal cual — SIN cambiar esta clave, ya tiene datos reales acumulados en producción desde Fase 3),
  # 'adset' (si el lead trae adset_id) y 'advert' (si además trae advert_id). dimension_id de
  # adset/advert es una clave compuesta "campaign_id::adset_id::nombre_o_id" (adset) /
  # "campaign_id::adset_id::advert_id::nombre_o_id" (advert) — ambos son dimensiones nuevas sin
  # datos previos, así que pueden llevar el nombre embebido: el builder solo lee revenue_rollups
  # (nunca revenue_leads), así que el nombre legible tiene que viajar dentro del propio
  # dimension_id, no resolverse aparte.
  def marketing_dimension_rows(account, date, ids, metric)
    campaign_id, adset_id, adset_name, advert_id, advert_name = ids
    rows = [row(account, date, 'campaign', campaign_id, metric)]
    return rows if adset_id.blank?

    rows << row(account, date, 'adset', "#{campaign_id}::#{adset_id}::#{adset_name.presence || adset_id}", metric)
    return rows if advert_id.blank?

    rows << row(account, date, 'advert', "#{campaign_id}::#{adset_id}::#{advert_id}::#{advert_name.presence || advert_id}", metric)
    rows
  end

  # dimension_id: stage. "entered" cuenta filas nuevas por fecha de entrada; "duration_seconds"
  # (sum_value) solo se agrega cuando la fila ya cerró (exited_at presente) — la fila abierta
  # actual no aporta duración todavía, se agregará en una corrida futura cuando cierre.
  def pipeline_stage_rows(account, since, until_at)
    entered = account.revenue_stage_events.where(window(:created_at, since, until_at)).pluck(:stage, :entered_at)
                     .map { |stage, entered_at| row(account, entered_at.to_date, 'pipeline_stage', stage, 'entered') }

    closed = account.revenue_stage_events.where.not(exited_at: nil).where(window(:created_at, since, until_at))
                    .pluck(:stage, :exited_at, :duration_seconds)
                    .map do |stage, exited_at, duration_seconds|
      row(account, exited_at.to_date, 'pipeline_stage', stage, 'duration_seconds', count: 1, sum_value: duration_seconds || 0)
    end

    entered + closed
  end

  # dimension_id: clave compuesta "campo:valor" (cta_used:true/false, intent_level:<valor>,
  # score_band:<rango>). metric "calls" = denominador, "appointments_after" = numerador (¿hubo un
  # appointment_created de ese contacto después del inicio de la llamada?). Asociación, no
  # causalidad — ver riesgos del plan de Fase 3.
  def call_conversion_rows(account, since, until_at)
    features = account.revenue_call_features.where(window(:created_at, since, until_at))
    appointments = appointments_after_lookup(account)

    features.find_each.flat_map do |feature|
      converted = appointment_after?(appointments, feature.revenue_contact_id, feature.started_at)
      call_conversion_dimensions(feature).flat_map do |dimension_id|
        conversion_pair(account, feature.started_at, 'call_conversion', dimension_id, converted)
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
  def objection_conversion_rows(account, since, until_at)
    contact_by_call = account.revenue_call_features.pluck(:call_id, :revenue_contact_id, :started_at)
                             .to_h { |call_id, contact_id, started_at| [call_id, [contact_id, started_at]] }
    appointments = appointments_after_lookup(account)

    CallAnalysis.where(account_id: account.id, status: 'completed').where(window(:analyzed_at, since, until_at)).find_each.flat_map do |analysis|
      contact_id, started_at = contact_by_call[analysis.call_id]
      next [] unless contact_id

      converted = appointment_after?(appointments, contact_id, started_at)
      Array(analysis.objections).filter_map { |o| o['category'] }.flat_map do |category|
        conversion_pair(account, analysis.analyzed_at, 'objection_conversion', category, converted)
      end
    end
  end

  def conversion_pair(account, date, dimension_type, dimension_id, converted)
    rows = [row(account, date.to_date, dimension_type, dimension_id, 'total')]
    rows << row(account, date.to_date, dimension_type, dimension_id, 'converted') if converted
    rows
  end

  def appointments_after_lookup(account)
    account.revenue_events.where(event_type: 'appointment_created').where.not(revenue_contact_id: nil)
           .pluck(:revenue_contact_id, :event_at).group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
  end

  def appointment_after?(appointments, revenue_contact_id, after_time)
    return false if revenue_contact_id.blank? || after_time.blank?

    Array(appointments[revenue_contact_id]).any? { |event_at| event_at > after_time }
  end
end
