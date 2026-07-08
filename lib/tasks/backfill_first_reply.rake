namespace :chatwoot do
  desc 'Backfill first_reply_created_at and first_response reporting events for existing conversations'
  task backfill_first_reply: :environment do
    account_id = ENV.fetch('ACCOUNT_ID', nil)
    scope = account_id ? Account.where(id: account_id) : Account.all

    scope.find_each do |account|
      conversations = account.conversations.where(first_reply_created_at: nil)
      updated = 0
      events_created = 0

      conversations.find_each do |conversation|
        first_human_reply = conversation.messages
          .where(message_type: :outgoing, sender_type: 'User', private: false)
          .where("(content_attributes->>'automation_rule_id') IS NULL")
          .where("(additional_attributes->>'campaign_id') IS NULL")
          .order(:created_at)
          .first

        next unless first_human_reply

        conversation.update_columns(
          first_reply_created_at: first_human_reply.created_at,
          waiting_since: nil
        )
        updated += 1

        next if ReportingEvent.exists?(conversation_id: conversation.id, name: 'first_response')

        # Use created_at as start (same fallback as last_non_human_activity when no bot events exist)
        start_event = ReportingEvent.where(
          conversation_id: conversation.id,
          name: %w[conversation_bot_handoff conversation_opened]
        ).order(event_end_time: :desc).first

        start_time = start_event&.event_end_time || conversation.created_at
        response_time = first_human_reply.created_at.to_i - start_time.to_i

        ReportingEvent.create!(
          name: 'first_response',
          value: response_time,
          value_in_business_hours: 0,
          account_id: account.id,
          inbox_id: conversation.inbox_id,
          user_id: first_human_reply.sender_id,
          conversation_id: conversation.id,
          event_start_time: start_time,
          event_end_time: first_human_reply.created_at
        )
        events_created += 1
      rescue StandardError => e
        puts "  Error en conversación #{conversation.id}: #{e.message}"
      end

      puts "Cuenta #{account.id} (#{account.name}): #{updated} conversaciones actualizadas, #{events_created} eventos creados"
    end

    puts 'Backfill completado.'
  end
end
