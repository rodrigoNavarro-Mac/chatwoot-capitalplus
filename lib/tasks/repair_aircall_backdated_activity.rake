namespace :chatwoot do
  desc 'Corrige el created_at de mensajes de llamadas de Aircall creados antes del fix de fechas ' \
       '(quedaron fechados el día del backfill en vez de la fecha real de la llamada), y recalcula ' \
       'last_activity_at/waiting_since de las conversaciones afectadas — correr una sola vez'
  task repair_aircall_backdated_activity: :environment do
    account_id = ENV.fetch('ACCOUNT_ID', nil)
    scope = account_id ? Account.where(id: account_id) : Account.all

    scope.find_each do |account|
      calls = Call.where(account_id: account.id, provider: :aircall).where.not(message_id: nil)
      fixed_messages = 0
      affected_conversation_ids = Set.new

      calls.find_each do |call|
        message = call.message
        next if message.blank? || call.started_at.blank?
        next if message.created_at.to_i == call.started_at.to_i

        # rubocop:disable Rails/SkipsModelValidations
        message.update_columns(created_at: call.started_at, updated_at: call.started_at)
        # rubocop:enable Rails/SkipsModelValidations
        affected_conversation_ids << call.conversation_id
        fixed_messages += 1
      rescue StandardError => e
        puts "  Error corrigiendo call #{call.id}: #{e.message}"
      end

      fixed_conversations = 0
      affected_conversation_ids.each do |conversation_id|
        conversation = account.conversations.find_by(id: conversation_id)
        next if conversation.blank?

        last_message = conversation.messages.where(private: false).order(created_at: :desc).first
        new_last_activity_at = conversation.messages.maximum(:created_at) || conversation.created_at
        new_waiting_since = last_message&.incoming? ? last_message.created_at : nil

        # rubocop:disable Rails/SkipsModelValidations
        conversation.update_columns(last_activity_at: new_last_activity_at, waiting_since: new_waiting_since)
        # rubocop:enable Rails/SkipsModelValidations
        fixed_conversations += 1
      rescue StandardError => e
        puts "  Error recalculando conversación #{conversation_id}: #{e.message}"
      end

      next if fixed_messages.zero?

      puts "Cuenta #{account.id} (#{account.name}): #{fixed_messages} mensajes corregidos, #{fixed_conversations} conversaciones recalculadas"
    end

    puts 'Reparación completada.'
  end
end
