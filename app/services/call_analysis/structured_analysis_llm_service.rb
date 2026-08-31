# Extracción estructurada por LLM de una llamada de Aircall ya transcrita — mismo patrón que
# Reports::WeeklyOpsAnalysisLlmService (response_format json_object, sanitize_json_response
# heredado de Llm::BaseAiService, ChatwootExceptionTracker en error).
#
# El LLM NUNCA calcula el score total ponderado ni decide metrics de talk ratio/preguntas — eso ya
# viene calculado en Ruby (ver Voice::ConversationMetricsCalculator, CallAnalysis::AnalyzeJob) y
# se le pasa como "verdad objetiva" en el prompt. El LLM solo clasifica, extrae y da sub-scores
# cualitativos por etapa del scorecard — el total lo calcula CallAnalysis::ScorecardCalculator,
# para poder re-ponderar sin volver a llamar al modelo.
class CallAnalysis::StructuredAnalysisLlmService < Llm::BaseAiService
  PROMPT_VERSION = 'v1'.freeze

  QUALIFICATION_KEYS = %w[
    intencion_vivir_invertir necesidad_concreta requisito_indispensable presupuesto
    forma_pago_credito momento_compra tomadores_decision alternativas_competencia
    bloqueo_principal siguiente_paso
  ].freeze

  OBJECTION_CATEGORIES = %w[
    financiera producto ubicacion entrega_preventa confianza necesidad_alternativa
    timing autoridad expectativa_fallida
  ].freeze

  RISK_TYPES = %w[
    improvisar_condiciones mensualidades_sin_contexto desconocer_requisitos
    incompatibilidad_tardia afirmaciones_absolutas compartir_condiciones_terceros
    desacreditar_competencia urgencia_antes_de_valor
  ].freeze

  EXPECTED_KEYS = %w[
    role role_confidence_note conversation_type confidence confidence_reason intent_level
    intent_signals outcome_type outcome_at outcome_evidence qualification_map objections
    contactability risks presentation_quality scorecard_stages questions_llm_adjusted
  ].freeze

  def initialize(account:, call:, project_name:, role_hint:, metrics:)
    super()
    @account = account
    @call = call
    @project_name = project_name
    @role_hint = role_hint
    @metrics = metrics
  end

  # { error: 'model_error' | 'invalid_format' } en fallo, o el hash de campos EXPECTED_KEYS en éxito.
  def generate
    response = chat.with_params(response_format: { type: 'json_object' })
                   .with_instructions(system_prompt)
                   .ask(user_prompt)
    parse_response(response.content)
  rescue RubyLLM::Error => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
    { error: 'model_error' }
  end

  private

  attr_reader :account, :call, :project_name, :role_hint, :metrics

  def parse_response(content)
    parsed = JSON.parse(sanitize_json_response(content))
    validate!(parsed)
    parsed.slice(*EXPECTED_KEYS).merge('objections' => sanitize_objections(parsed['objections']), 'risks' => sanitize_risks(parsed['risks']))
  rescue JSON::ParserError => e
    Rails.logger.error("[CallAnalysis::StructuredAnalysisLlmService] error parseando respuesta: #{e.message}")
    { error: 'invalid_format' }
  rescue InvalidClassificationError => e
    Rails.logger.error("[CallAnalysis::StructuredAnalysisLlmService] respuesta incompleta: #{e.message}")
    { error: 'invalid_format' }
  end

  class InvalidClassificationError < StandardError; end

  # Bloquea solo si falta la clasificación mínima indispensable (rol/tipo/resultado/confianza) —
  # una objeción o riesgo individual con categoría fuera del vocabulario cerrado se descarta en
  # #sanitize_objections/#sanitize_risks en vez de invalidar todo el análisis.
  def validate!(parsed)
    required = %w[role conversation_type confidence outcome_type]
    missing = required.select { |key| parsed[key].blank? }
    raise InvalidClassificationError, "faltan claves: #{missing.join(', ')}" if missing.any?
    raise InvalidClassificationError, "role inválido: #{parsed['role']}" unless CallAnalysis::ROLES.include?(parsed['role'])
  end

  def sanitize_objections(objections)
    Array(objections).select { |o| o.is_a?(Hash) && OBJECTION_CATEGORIES.include?(o['category']) }
  end

  def sanitize_risks(risks)
    Array(risks).select { |r| r.is_a?(Hash) && RISK_TYPES.include?(r['type']) }
  end

  def stage_keys_hint
    "Setter: #{CallAnalysis::ScorecardConfig.stage_keys('setter').join(', ')}. " \
      "Asesor: #{CallAnalysis::ScorecardConfig.stage_keys('asesor').join(', ')}."
  end

  def system_prompt
    <<~PROMPT
      Eres un analista de calidad de llamadas de ventas para una inmobiliaria que vende varios
      desarrollos. Recibes la transcripción diarizada (hablante + timestamp) de UNA llamada
      telefónica entre un agente (Setter o Asesor) y un contacto/lead, más métricas objetivas ya
      calculadas (talk ratio, preguntas, monólogo más largo — NO las recalcules).

      DEFINICIÓN DE ROL (regla temporal, no de tono de la conversación):
      - "setter": desde el primer contacto hasta que la cita realmente sucede.
      - "asesor": desde que la reunión/cita ya se realizó, hasta cierre o resolución.
      Se te da una pista de rol (role_hint) calculada por fecha de la llamada vs. si ya hubo una
      cita realizada — CONFÍRMALA o CONTRADÍCELA citando evidencia textual. Si la contradices,
      tu campo "confidence" debe bajar a "low" o "medium" y "role_confidence_note" debe explicar
      por qué.

      TIPOLOGÍA DE CONVERSACIÓN (elige exactamente una, vocabulario cerrado):
      prospeccion_inicial, seguimiento_pre_cita, confirmacion_cita, post_visita, reactivacion.

      MAPA DE CALIFICACIÓN — vocabulario cerrado de 10 elementos, usa exactamente estas claves en
      "qualification_map" (cada una: {"captured": true|false, "evidence": "cita textual o null"}).
      NO exijas los 10 en cada llamada — mide completitud real según el tipo/momento:
      #{QUALIFICATION_KEYS.join(', ')}

      OBJECIONES — taxonomía cerrada, cada objeción detectada en "objections" con esta forma:
      {"category": una de [#{OBJECTION_CATEGORIES.join(', ')}], "subtype": "string libre corto",
      "quote": "cita textual", "recognized": true|false, "explored": true|false,
      "response": "cómo se respondió", "returned_to_next_step": true|false}.
      La contactabilidad (dificultad para contactar al lead, no contestar, etc.) NO es una
      objeción — repórtala aparte en "contactability": {"issue": true|false, "notes": "string"}.

      INTENCIÓN — "intent_level" en alta/media/baja, con "intent_signals" (array de strings, las
      señales textuales que sustentan la clasificación: pregunta por apartado/enganche con sus
      datos, propone fecha, pregunta por unidad específica, presupuesto/crédito resuelto, urgencia
      externa real, involucrará al decisor).

      RESULTADO — "outcome_type" en cita/seguimiento/accion_sin_fecha/solo_informacion/sin_avance,
      "outcome_at" (fecha ISO8601 si aplica, si no null), "outcome_evidence" (cita textual).
      REGLA DURA con contraejemplo: "te mando información y me dices" NUNCA es "seguimiento" — es
      "solo_informacion" o "sin_avance". Solo es "seguimiento" si hay una fecha/momento concreto
      propuesto por cualquiera de las dos partes.

      RIESGOS DE DOMINIO — vocabulario cerrado de 8, cada uno detectado en "risks":
      {"type": uno de [#{RISK_TYPES.join(', ')}], "evidence": "cita textual"}. No inventes tipos
      nuevos; si no aplica ninguno, "risks" debe ser [].

      CALIDAD DE PRESENTACIÓN — "presentation_quality": {"generic_or_connected": "generica"|
      "conectada_a_necesidad", "used_mirror_summary": true|false,
      "prioritized_relevant_attributes": true|false, "avoided_full_datasheet_dump": true|false,
      "notes": "string corto"}.

      SCORECARD — "scorecard_stages": un objeto con sub-score 0-100 y evidencia por cada etapa
      aplicable SEGÚN EL ROL FINAL que reportaste (usa exactamente estos nombres de etapa, nunca
      inventes otros): #{stage_keys_hint}
      Formato por etapa: {"score": 0-100, "evidence": "string corto"}. NO calcules ni incluyas un
      total ponderado — eso se calcula fuera de tu respuesta.

      CONFIANZA — "confidence" en low/medium/high + "confidence_reason" (string corto). Usa "low"
      cuando la transcripción sea ambigua, falte contexto, o contradigas el role_hint sin evidencia
      clara.

      OPCIONAL — "questions_llm_adjusted": si notas que el conteo objetivo de preguntas
      (proporcionado en metrics) claramente subestimó o sobrestimó por errores de transcripción,
      da tu propio conteo {"open": n, "closed": n}; si no tienes ajuste, omite esta clave.

      Nunca inventes una cita textual que no esté en la transcripción. Si un campo no aplica o no
      hay evidencia suficiente, usa null o un array vacío — nunca inventes contenido para rellenar.

      Responde ÚNICAMENTE con un objeto JSON con las claves: #{EXPECTED_KEYS.join(', ')}.
    PROMPT
  end

  def user_prompt
    <<~PROMPT
      Proyecto/desarrollo: #{project_name}
      role_hint: #{role_hint || 'sin señal clara — decide con la evidencia de la llamada'}
      Métricas objetivas ya calculadas (no las recalcules): #{metrics.to_json}

      Transcripción diarizada (speaker, start_seconds, text), en orden cronológico:
      #{formatted_segments}
    PROMPT
  end

  def formatted_segments
    Array(call.transcript_segments).map { |seg| "#{seg['start_seconds']}s - #{seg['speaker']}: #{seg['text']}" }.join("\n")
  end
end
