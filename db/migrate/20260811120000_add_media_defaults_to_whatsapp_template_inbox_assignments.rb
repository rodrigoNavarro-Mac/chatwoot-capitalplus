class AddMediaDefaultsToWhatsappTemplateInboxAssignments < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_template_inbox_assignments, :media_url, :string
    add_column :whatsapp_template_inbox_assignments, :media_name, :string
  end
end
