# Punto de entrada para el webhook de Aircall en tiempo real. Solo procesa el evento `call.ended`
# (Aircall lo dispara ~30s después de colgar, ya con duración/grabación resueltas — ver
# developer.aircall.io/tutorials/webhooks-guide) y delega el procesamiento del call object a
# Crm::Aircall::CallProcessor, compartido con Crm::Aircall::CallHistoryBackfillService (backfill
# histórico vía la REST API) para que ambos flujos reflejen una llamada de forma idéntica.
class Crm::Aircall::InboundWebhookService
  RELEVANT_EVENT = 'call.ended'.freeze

  def initialize(account, params)
    @account = account
    @params = params.with_indifferent_access
  end

  def perform
    return unless event == RELEVANT_EVENT

    Crm::Aircall::CallProcessor.new(account: account, call_data: data).perform
  end

  private

  attr_reader :account, :params

  def event
    params[:event]
  end

  def data
    params[:data] || {}
  end
end
