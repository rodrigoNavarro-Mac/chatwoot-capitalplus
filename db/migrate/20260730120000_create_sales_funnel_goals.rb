# frozen_string_literal: true

class CreateSalesFunnelGoals < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_funnel_goals do |t|
      t.references :account, null: false, index: true
      t.string :development_key, null: false
      t.string :stage, null: false
      t.date :period_month, null: false
      t.decimal :target_percent, precision: 5, scale: 2, null: false, default: 0

      t.timestamps
    end

    add_index :sales_funnel_goals, [:account_id, :development_key, :stage, :period_month],
              unique: true, name: 'index_sales_funnel_goals_on_account_development_stage_period'
  end
end
