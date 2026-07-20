class EnqueueEncryptHookSettingsJob < ActiveRecord::Migration[7.1]
  def up
    Migration::EncryptHookSettingsJob.perform_later
  end

  def down; end
end
