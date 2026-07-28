class AddIndexToConversationsWhatsappWindowExpiresAt < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :conversations, :whatsapp_window_expires_at,
              name: 'index_conversations_on_whatsapp_window_expires_at',
              where: 'whatsapp_window_expires_at IS NOT NULL',
              algorithm: :concurrently
  end
end
