# Redacta el análisis ejecutivo en español del reporte semanal operativo a partir de los KPIs ya
# calculados por V2::Reports::WeeklyOpsReportBuilder. No recibe datos crudos de contactos —
# solo los agregados — para no exponer PII al LLM.
class Reports::WeeklyOpsAnalysisLlmService < Llm::BaseAiService
  def initialize(account:, kpis:)
    super()
    @account = account
    @kpis = kpis
  end

  def generate
    chat.with_instructions(system_prompt).ask(user_prompt).content
  rescue RubyLLM::Error => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
    nil
  end

  private

  attr_reader :account, :kpis

  def system_prompt
    <<~PROMPT
      Eres un analista de operaciones comerciales para un negocio que vende distintos desarrollos
      inmobiliarios y atiende a sus leads por WhatsApp dentro de Chatwoot. Recibes los KPIs ya
      calculados de UN desarrollo para una semana: volumen de leads, tiempos de contacto, embudo
      de ventas (Zoho), desempeño de las cadencias de seguimiento y de las campañas masivas.

      Escribe un análisis ejecutivo breve en español, en prosa (no uses listas ni viñetas), que:
      - destaque 2 o 3 hallazgos accionables de la semana, positivos o negativos,
      - compare contra el periodo anterior cuando ese dato esté disponible en el JSON,
      - nunca invente cifras que no estén presentes en los datos entregados,
      - interprete los números en vez de solo repetirlos.

      Máximo 180 palabras.
    PROMPT
  end

  def user_prompt
    "KPIs del desarrollo \"#{kpis[:inbox_name]}\" (JSON):\n\n#{kpis.to_json}"
  end
end
