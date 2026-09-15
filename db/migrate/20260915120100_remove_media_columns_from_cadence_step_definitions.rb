class RemoveMediaColumnsFromCadenceStepDefinitions < ActiveRecord::Migration[7.1]
  def change
    remove_column :cadence_step_definitions, :media_url, :string
    remove_column :cadence_step_definitions, :media_type, :string
    remove_column :cadence_step_definitions, :media_name, :string
  end
end
