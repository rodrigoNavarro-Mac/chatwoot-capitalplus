# Encola CallAnalysis (vía Crm::Aircall::RecordingAndTranscriptJob) para llamadas de Aircall ya
# completadas en un rango de fechas que todavía no tienen análisis — idempotente por call_id, así
# que correrlo dos veces sobre el mismo rango nunca duplica ni reprocesa las que ya tienen
# call_analysis. Usado por `bin/rails chatwoot:backfill_call_intelligence` (ver ese rake task para
# el flujo de dry-run).
#
# A propósito NO reusa Crm::Aircall::CallHistoryBackfillService: ese servicio reprocesa TODO el
# historial de la cuenta de una sola vez (llamado desde CallProcessor, que ahora también encola
# call_intelligence) sin poder acotar por fecha — no sirve para un backfill selectivo de un mes.
class Crm::Aircall::CallIntelligenceBackfillService
  RATE_LIMIT_DELAY = 1.1 # segundos entre requests; Aircall permite 60/min (igual que CallHistoryBackfillService)

  def initialize(account:, from:, to:)
    @account = account
    @from = from
    @to = to
  end

  def pending_calls
    Call.where(account_id: account.id, provider: :aircall, status: 'completed', started_at: from..to)
        .where.missing(:call_analysis)
        .order(:started_at)
  end

  # Encola el análisis de cada llamada pendiente y devuelve cuántas se encolaron.
  def perform!
    urls = recording_urls_by_call_id
    queued = 0

    pending_calls.find_each do |call|
      Crm::Aircall::RecordingAndTranscriptJob.perform_later(call.id, recording_url: urls[call.provider_call_id])
      queued += 1
    end

    queued
  end

  private

  attr_reader :account, :from, :to

  def hook
    @hook ||= account.hooks.find_by(app_id: 'aircall', status: 'enabled')
  end

  def client
    @client ||= Crm::Aircall::Api::CallsClient.new(hook)
  end

  # La URL de grabación no se guarda en `calls` (solo llega en el payload del webhook original) —
  # hay que volver a pedirla del historial de Aircall, por mes para no exceder el límite de 10,000
  # resultados por consulta paginada que documenta Crm::Aircall::CallHistoryBackfillService.
  def recording_urls_by_call_id
    urls = {}
    each_month_window { |window_from, window_to| merge_month_urls!(urls, window_from, window_to) }
    urls
  end

  def each_month_window
    month_start = from.beginning_of_month

    while month_start <= to
      yield [month_start, from].max, [month_start.end_of_month, to].min
      month_start = month_start.next_month.beginning_of_month
    end
  end

  def merge_month_urls!(urls, window_from, window_to)
    page = 1

    loop do
      response = client.list(from: window_from, to: window_to, page: page)
      Array(response['calls']).each { |c| urls[c['id'].to_s] = c['recording'] }
      sleep(RATE_LIMIT_DELAY)

      break if response.dig('meta', 'next_page_link').blank?

      page += 1
    end
  end
end
