# rubocop:disable Metrics/BlockLength
namespace :cadences do
  desc 'Backfill cadence_step_definitions from the legacy STEPS constant, for every WhatsApp inbox. Idempotent.'
  task backfill_step_definitions: :environment do
    Inbox.where(channel_type: 'Channel::Whatsapp').find_each do |inbox|
      result = Cadences::LegacyBackfillService.new(inbox: inbox).call
      puts "[cadences] inbox #{inbox.id}: #{result}"
    end
  end

  desc 'Stamp steps_snapshot on cadence_enrollments created before the migration to cadence_step_definitions. Idempotent.'
  task backfill_enrollment_snapshots: :environment do
    CadenceEnrollment.where(steps_snapshot: []).find_each do |enrollment|
      snapshot = Cadences::StepsRepository.snapshot_for(enrollment.cadence_definition)
      enrollment.update_column(:steps_snapshot, snapshot) # rubocop:disable Rails/SkipsModelValidations
      puts "[cadences] enrollment #{enrollment.id}: snapshot con #{snapshot.size} pasos"
    end
  end

  desc 'Regenerate steps_snapshot for one enrollment from the live config (fixes a captured error, e.g. wrong media_url). Preserves current_step.'
  task :resync_enrollment_snapshot, [:enrollment_id] => :environment do |_task, args|
    enrollment = CadenceEnrollment.find(args.fetch(:enrollment_id))
    snapshot = Cadences::StepsRepository.snapshot_for(enrollment.cadence_definition)
    enrollment.update!(steps_snapshot: snapshot)
    puts "[cadences] enrollment #{enrollment.id}: steps_snapshot resincronizado " \
         "(#{snapshot.size} pasos), current_step=#{enrollment.current_step} sin cambios"
  end

  desc 'Enroll pre-existing WhatsApp conversations that already got a template sent (manual/API/Zoho) into the ' \
       'cadence configured for their inbox, resuming at the matching step instead of restarting from step 1. ' \
       'Idempotent (skips conversations already enrolled). Pass an inbox_id to scope the run to a single inbox.'
  task :enroll_past_leads, [:inbox_id] => :environment do |_task, args|
    scope = Conversation.joins(:inbox)
                        .where(inboxes: { channel_type: 'Channel::Whatsapp' })
                        .where.not(id: CadenceEnrollment.select(:conversation_id))
    scope = scope.where(inbox_id: args[:inbox_id]) if args[:inbox_id].present?

    counts = Hash.new(0)
    scope.find_each do |conversation|
      result = Cadences::PastLeadEnrollmentService.new(conversation: conversation).call
      counts[result.status] += 1
      puts "[cadences] conversation #{result.conversation_id}: #{result.status} (#{result.detail})"
    end
    puts "[cadences] done. #{counts.map { |status, n| "#{status}=#{n}" }.join(' ')}"
  end
end
# rubocop:enable Metrics/BlockLength
