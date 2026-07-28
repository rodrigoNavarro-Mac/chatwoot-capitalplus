class AddWhatsappWindowExpiresAtToConversations < ActiveRecord::Migration[7.1]
  def change
    add_column :conversations, :whatsapp_window_expires_at, :datetime
  end
end
