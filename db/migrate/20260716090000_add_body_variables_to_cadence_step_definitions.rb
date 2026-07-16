class AddBodyVariablesToCadenceStepDefinitions < ActiveRecord::Migration[7.1]
  def change
    add_column :cadence_step_definitions, :body_variables, :jsonb, null: false, default: {}
  end
end
