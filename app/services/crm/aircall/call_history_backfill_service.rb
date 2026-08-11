# Trae el historial completo de llamadas de Aircall vía su REST API (GET /v1/calls) y las
# procesa con Crm::Aircall::CallProcessor — el mismo procesamiento que usa el webhook en tiempo
# real (Crm::Aircall::InboundWebhookService), así que el resultado es idéntico sin importar si la
# llamada se reflejó justo cuando terminó o meses después vía este backfill.
#
# Aircall limita cada consulta paginada a 10,000 resultados (incluso paginando) y recomienda
# explícitamente acotar por from/to para historiales grandes (developers.aircall.io) — por eso se
# itera mes por mes hacia atrás desde el mes actual en vez de pedir todo de una sola vez. Se
# detiene automáticamente en cuanto un mes no devuelve ninguna llamada en su primera página: ahí
# se acabó el historial real de la cuenta en Aircall, sin necesidad de conocer de antemano desde
# cuándo existe la cuenta.
#
# Pensado para correrse una sola vez por consola (rails runner), no como un job recurrente.
class Crm::Aircall::CallHistoryBackfillService
  RATE_LIMIT_DELAY = 1.1 # segundos entre requests; Aircall permite 60/min

  def initialize(account)
    @account = account
  end

  def perform
    return if hook.blank?

    month_start = Time.current.beginning_of_month
    total = 0

    loop do
      processed_in_month = backfill_month(month_start)
      break if processed_in_month.zero?

      total += processed_in_month
      month_start -= 1.month
    end

    total
  end

  private

  attr_reader :account

  def hook
    @hook ||= account.hooks.find_by(app_id: 'aircall', status: 'enabled')
  end

  def client
    @client ||= Crm::Aircall::Api::CallsClient.new(hook)
  end

  def backfill_month(month_start)
    from = month_start
    to = month_start.end_of_month
    page = 1
    processed = 0

    loop do
      response = client.list(from: from, to: to, page: page)
      calls = response['calls'] || []
      calls.each { |call_data| process(call_data) }
      processed += calls.size

      sleep(RATE_LIMIT_DELAY)

      break if response.dig('meta', 'next_page_link').blank?

      page += 1
    end

    processed
  end

  def process(call_data)
    Crm::Aircall::CallProcessor.new(account: account, call_data: call_data).perform
  rescue StandardError => e
    Rails.logger.error("[AIRCALL BACKFILL] account ##{account.id} call_id=#{call_data['id']} error=#{e.message}")
  end
end
