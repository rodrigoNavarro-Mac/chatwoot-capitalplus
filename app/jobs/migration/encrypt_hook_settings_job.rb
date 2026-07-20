class Migration::EncryptHookSettingsJob < ApplicationJob
  queue_as :async_database_migration

  def perform
    return unless Chatwoot.encryption_configured?

    stats = { checked: 0, rewritten: 0 }

    Integrations::Hook.find_each do |hook|
      stats[:checked] += 1
      next if hook.settings.blank?

      # ActiveRecord skips serializing attributes whose in-memory value is unchanged, so a
      # plain `hook.save` on a legacy plaintext row does NOT re-run it through the new
      # `encrypts :settings` type and leaves it in plaintext. Force it dirty so the encrypted
      # type actually gets applied to the existing value on write.
      hook.send(:attribute_will_change!, 'settings')
      hook.save!(validate: false)
      stats[:rewritten] += 1
    end

    Rails.logger.info("[hook-settings-encryption-backfill] completed #{stats.inspect}")
    stats
  end
end
