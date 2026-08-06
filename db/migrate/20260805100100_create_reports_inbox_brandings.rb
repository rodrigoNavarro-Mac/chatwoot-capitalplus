# frozen_string_literal: true

class CreateReportsInboxBrandings < ActiveRecord::Migration[7.1]
  def change
    create_table :reports_inbox_brandings do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false
      t.string :accent_color

      t.timestamps
    end

    add_index :reports_inbox_brandings, :inbox_id, unique: true
    add_index :reports_inbox_brandings, :account_id
  end
end
