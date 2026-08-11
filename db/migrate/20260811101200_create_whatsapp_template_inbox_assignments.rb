class CreateWhatsappTemplateInboxAssignments < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_template_inbox_assignments do |t|
      t.references :account, null: false
      t.references :inbox, null: false
      t.string :template_name, null: false

      t.timestamps
    end

    add_index :whatsapp_template_inbox_assignments,
              [:account_id, :template_name, :inbox_id],
              unique: true,
              name: 'index_wa_template_inbox_assignments_on_account_template_inbox'
    add_index :whatsapp_template_inbox_assignments, [:account_id, :inbox_id]
  end
end
