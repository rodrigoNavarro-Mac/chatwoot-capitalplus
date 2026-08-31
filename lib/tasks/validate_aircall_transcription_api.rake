namespace :chatwoot do
  desc 'Valida contra una llamada real el shape del JSON que devuelve el endpoint de transcripción ' \
       'de Aircall AI (GET /v1/calls/:id/transcription) — paso bloqueante antes de activar el feature ' \
       'flag call_intelligence en producción (ver comentario de cabecera de ' \
       'Crm::Aircall::Api::TranscriptionClient). Solo imprime la respuesta cruda, no escribe nada en BD.' \
       "\nUso: ACCOUNT_ID=87 [PROVIDER_CALL_ID=123456] bin/rails chatwoot:validate_aircall_transcription_api" \
       "\nSin PROVIDER_CALL_ID, usa la llamada de Aircall más reciente de la cuenta."
  task validate_aircall_transcription_api: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    hook = account.hooks.find_by(app_id: 'aircall', status: 'enabled')
    raise "La cuenta #{account.id} no tiene un hook de Aircall habilitado" if hook.blank?

    provider_call_id = ENV.fetch('PROVIDER_CALL_ID', nil) || most_recent_aircall_call_id(account)
    raise "La cuenta #{account.id} no tiene ninguna llamada de Aircall registrada" if provider_call_id.blank?

    puts "Consultando transcripción de la llamada #{provider_call_id} (cuenta #{account.id})..."
    response = Crm::Aircall::Api::TranscriptionClient.new(hook).raw_response(provider_call_id)

    puts "HTTP #{response.code}"
    puts response.body

    next unless response.code == 200

    puts "\n--- Normalización actual (Crm::Aircall::Api::TranscriptionClient#fetch_segments) ---"
    segments = Crm::Aircall::Api::TranscriptionClient.new(hook).fetch_segments(provider_call_id)
    pp segments
    puts "\nRevisa a mano si 'speaker'/'start_seconds'/'text' quedaron bien poblados arriba. " \
         'Si no, ajusta #normalize_utterance en transcription_client.rb antes de activar el flag.'
  end

  def most_recent_aircall_call_id(account)
    Call.where(account: account, provider: :aircall).order(started_at: :desc).limit(1).pick(:provider_call_id)
  end
end
