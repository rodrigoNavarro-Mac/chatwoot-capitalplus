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
end
