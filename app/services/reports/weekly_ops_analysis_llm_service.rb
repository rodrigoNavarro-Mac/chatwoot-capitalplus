# Redacta en una sola llamada al LLM: el análisis ejecutivo general del reporte semanal operativo
# Y una frase corta de interpretación por cada card individual del reporte (ver CARD_KEYS) — todo
# a partir de los KPIs ya calculados por V2::Reports::WeeklyOpsReportBuilder. No recibe datos
# crudos de contactos — solo los agregados — para no exponer PII al LLM.
#
# Una sola llamada (no 16) para no multiplicar latencia/costo — se le pide al modelo un único
# objeto JSON con la clave "executive_summary" más una clave por card (ver CARD_KEYS), y se separa
# del lado de Ruby. Mismo patrón que Captain::Llm::ContactNotesService: response_format json_object
# + sanitize_json_response (heredado de Llm::BaseAiService) antes de JSON.parse.
class Reports::WeeklyOpsAnalysisLlmService < Llm::BaseAiService
  # Claves que el LLM puede devolver para el mini-análisis por card, en el mismo orden en que
  # aparecen en el reporte (ver WeeklyOpsReport.vue) — el LLM omite la clave cuando la sección
  # correspondiente de kpis no trae datos esa semana.
  CARD_KEYS = %w[
    leads_timeline pipeline zoho_pipeline_status deals_activity contact_time contact_time_by_period
    by_advisor conversion_totals zoho_source quality_by_source channel_comparison
    zoho_owner discard_reasons schedule_distribution aircall_calls cadences
  ].freeze

  def initialize(account:, kpis:)
    super()
    @account = account
    @kpis = kpis
  end

  # { executive_summary: String|nil, card_analyses: { "contact_time" => String, ... } }
  def generate
    response = chat.with_params(response_format: { type: 'json_object' })
                    .with_instructions(system_prompt)
                    .ask(user_prompt)
    parse_response(response.content)
  rescue RubyLLM::Error => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
    { executive_summary: nil, card_analyses: {} }
  end

  private

  attr_reader :account, :kpis

  def parse_response(content)
    parsed = JSON.parse(sanitize_json_response(content))
    {
      executive_summary: parsed['executive_summary'],
      card_analyses: parsed.slice(*CARD_KEYS)
    }
  rescue JSON::ParserError => e
    Rails.logger.error("[Reports::WeeklyOpsAnalysisLlmService] error parseando respuesta: #{e.message}")
    { executive_summary: nil, card_analyses: {} }
  end

  def system_prompt
    <<~PROMPT
      Eres un analista de operaciones comerciales para un negocio que vende distintos desarrollos
      inmobiliarios y atiende a sus leads por WhatsApp dentro de Chatwoot. Recibes los KPIs ya
      calculados de UN desarrollo para un periodo determinado, en JSON.

      REGLA MÁS IMPORTANTE: quien lee esto ya está viendo la gráfica o la tabla junto a tu texto.
      Nunca te limites a describir lo que ya es obvio a simple vista (que un número subió, que una
      barra es la más alta, que el total es X) — eso no aporta nada. Cada frase debe hacer UNA de
      estas dos cosas:
      (a) cruzar ese dato con otra sección del JSON para revelar algo que no se ve mirando solo esa
          card (causa probable, correlación, contradicción entre dos métricas), o
      (b) señalar un detalle específico y no obvio dentro de esa misma sección (un valor atípico,
          una proporción que no cuadra, algo que contradice la tendencia general).
      Si después de intentar (a) y (b) el dato es demasiado plano para decir algo que no sea obvio,
      omite esa clave — mejor omitir que rellenar con una obviedad.

      Responde ÚNICAMENTE con un objeto JSON con estas claves (usa exactamente estos nombres):

      "executive_summary": análisis ejecutivo en prosa (sin listas ni viñetas), 2-3 hallazgos que
      crucen información entre distintas secciones del JSON (no una lista de KPIs sueltos),
      comparando contra el periodo anterior cuando ese dato esté disponible. Máximo 180 palabras.

      Por cada una de las claves siguientes, UNA sola frase corta (máximo 25 palabras), en tono
      directo y ejecutivo, aplicando la regla de arriba. Si la sección correspondiente del JSON de
      entrada está vacía, nula, o no trae suficiente contexto para decir algo que no sea obvio,
      OMITE esa clave por completo del JSON de salida — nunca escribas "sin datos" ni inventes una
      cifra que no esté en el JSON de entrada:

      - "leads_timeline": kpis.zoho_leads_timeline — no describas si subió o bajó (ya se ve en la
        gráfica); cruza el volumen con kpis.schedule_distribution o kpis.contact_time_by_period_of_week
        (¿el patrón de llegada de leads presiona algún horario en particular?), o compáralo contra
        kpis.comparison.zoho_leads_timeline si el patrón cambió de forma notable.
      - "pipeline": kpis.pipeline.stages — no repitas cuál etapa cae más (ya se ve en el embudo);
        relaciona esa caída con kpis.contact_time, kpis.by_advisor o kpis.schedule_distribution para
        sugerir una causa probable.
      - "zoho_pipeline_status": kpis.zoho_leads.by_status_new (leads nuevos del periodo, comparable
        contra kpis.pipeline.stages) y kpis.zoho_leads.by_status_follow_up (leads viejos que se
        tocaron este periodo, sin equivalente en el embudo) — cruza by_status_new contra
        kpis.pipeline.stages: ¿el estado en Zoho y la etapa del embudo interno cuentan la misma
        historia, o hay un desfase que sugiere que el CRM no se está actualizando al mismo ritmo que
        la conversación? Si by_status_follow_up muestra mucho volumen, puedes señalar cuánto trabajo
        de seguimiento hay más allá de los leads nuevos.
      - "deals_activity": kpis.deals_activity (deals CREADOS este periodo, sin importar cuándo llegó
        el lead — a diferencia de kpis.pipeline, que solo cuenta deals de leads nuevos del periodo)
        — cruza contra kpis.pipeline.stages: si deals_activity.total es notablemente mayor que la
        etapa "has_deal" del embudo, señala que hay deals de leads viejos avanzando esta semana que
        el embudo de cohorte no refleja.
      - "contact_time": kpis.contact_time — cruza first_response/reply_time contra kpis.by_advisor
        (¿un asesor específico arrastra la mediana?) o contra kpis.comparison.contact_time.
      - "contact_time_by_period": kpis.contact_time_by_period_of_week — cruza la diferencia
        semana/fin de semana contra kpis.schedule_distribution (¿cuántos leads llegan realmente en
        ese horario débil?) en vez de solo reportar los minutos.
      - "by_advisor": kpis.by_advisor — cruza conversations_count contra contact_time por asesor
        (¿el que más atiende es también el más lento?) o contra kpis.zoho_leads.by_owner si un
        asesor no aparece ahí pero sí en Chatwoot.
      - "conversion_totals": kpis.conversion_totals — cruza la proporción convertidos/descartados
        contra kpis.zoho_leads.discard_reasons (motivo principal) o contra kpis.contact_time
        (¿el tiempo de respuesta explica parte del descarte?).
      - "zoho_source": kpis.zoho_leads.by_source — cruza el volumen por fuente contra
        kpis.zoho_leads.quality_by_source: ¿la fuente con más leads es también la de mejor calidad,
        o hay una contradicción ahí?
      - "quality_by_source": kpis.zoho_leads.quality_by_source — señala la fuente con mejor
        proporción calidad/volumen aunque no sea la de más leads, cruzando contra by_source.
      - "channel_comparison": compara kpis.zoho_leads.by_source contra
        kpis.comparison.zoho_leads.by_source — no solo digas qué canal creció más; cruza ese cambio
        de volumen contra kpis.zoho_leads.quality_by_source (¿el canal que más creció es de buena
        calidad, o el crecimiento es "ruido"?).
      - "zoho_owner": kpis.zoho_leads.by_owner — cruza la concentración de leads por dueño contra
        kpis.by_advisor (¿la carga en Zoho coincide con quién realmente atiende en Chatwoot?).
      - "discard_reasons": kpis.zoho_leads.discard_reasons — cruza el motivo principal contra
        kpis.zoho_leads.by_source o kpis.schedule_distribution (¿ese motivo se concentra en una
        fuente o en leads que llegan fuera de horario?).
      - "schedule_distribution": kpis.schedule_distribution — cruza el % fuera de horario contra
        kpis.contact_time_by_period_of_week (¿el fin de semana ya es lento Y además llega ahí buena
        parte del volumen?) en vez de solo dar el porcentaje.
      - "aircall_calls": kpis.aircall_calls — cruza la tasa de contestación contra kpis.contact_time
        o kpis.by_advisor si hay desglose por asesor en esta sección.
      - "cadences": kpis.cadences — cruza response_rate contra kpis.zoho_leads.discard_reasons o
        kpis.conversion_totals (¿los leads que no responden a la cadencia terminan descartados?).

      Nunca inventes cifras que no estén en el JSON de entrada — si el cruce que quieres hacer
      requiere un dato que no está en el JSON, usa otro cruce o, si no hay ninguno posible, omite
      la clave.
    PROMPT
  end

  def user_prompt
    "KPIs del desarrollo \"#{kpis[:inbox_name]}\" (JSON):\n\n#{kpis.to_json}"
  end
end
