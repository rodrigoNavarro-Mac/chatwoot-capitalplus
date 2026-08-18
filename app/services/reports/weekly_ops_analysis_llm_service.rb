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
    leads_timeline pipeline zoho_pipeline_status contact_time contact_time_by_period
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

      Responde ÚNICAMENTE con un objeto JSON con estas claves (usa exactamente estos nombres):

      "executive_summary": análisis ejecutivo en prosa (sin listas ni viñetas), 2-3 hallazgos
      accionables de la semana, comparando contra el periodo anterior cuando ese dato esté
      disponible en el JSON. Máximo 180 palabras.

      Por cada una de las claves siguientes, UNA sola frase corta (máximo 25 palabras), en tono
      directo y ejecutivo, que interprete el número (no lo repita tal cual) y diga si es bueno,
      malo o normal para la operación. Si la sección correspondiente del JSON de entrada está
      vacía, nula, o no trae suficiente contexto para opinar con criterio, OMITE esa clave por
      completo del JSON de salida — nunca escribas "sin datos" ni inventes una cifra que no esté
      en el JSON de entrada:

      - "leads_timeline": sobre kpis.zoho_leads_timeline — ¿el volumen de leads subió o bajó en el periodo?
      - "pipeline": sobre kpis.pipeline.stages — ¿en qué etapa del embudo se están cayendo más leads?
      - "zoho_pipeline_status": sobre kpis.zoho_leads.by_status — ¿dónde se está acumulando el pipeline?
      - "contact_time": sobre kpis.contact_time (first_response, reply_time en minutos) — ¿se contesta rápido?
      - "contact_time_by_period": sobre kpis.contact_time_by_period_of_week — ¿hay diferencia fuerte entre semana y fin de semana?
      - "by_advisor": sobre kpis.by_advisor — ¿algún asesor destaca o está muy por debajo del resto?
      - "conversion_totals": sobre kpis.conversion_totals (convertidos vs descartados) — ¿la proporción es sana?
      - "zoho_source": sobre kpis.zoho_leads.by_source — ¿de dónde viene la mayoría de los leads?
      - "quality_by_source": sobre kpis.zoho_leads.quality_by_source — ¿qué fuente trae leads de mejor calidad?
      - "channel_comparison": compara kpis.zoho_leads.by_source contra kpis.comparison.zoho_leads.by_source — ¿qué fuente creció o cayó más semana a semana?
      - "zoho_owner": sobre kpis.zoho_leads.by_owner — ¿un solo dueño concentra los leads en Zoho?
      - "discard_reasons": sobre kpis.zoho_leads.discard_reasons — ¿cuál es el motivo de descarte más común?
      - "schedule_distribution": sobre kpis.schedule_distribution — ¿los leads llegan dentro o fuera de horario laboral?
      - "aircall_calls": sobre kpis.aircall_calls — ¿qué tan buena es la tasa de contestación de llamadas?
      - "cadences": sobre kpis.cadences — ¿las cadencias de seguimiento están funcionando (response_rate)?

      Nunca inventes cifras que no estén en el JSON de entrada.
    PROMPT
  end

  def user_prompt
    "KPIs del desarrollo \"#{kpis[:inbox_name]}\" (JSON):\n\n#{kpis.to_json}"
  end
end
