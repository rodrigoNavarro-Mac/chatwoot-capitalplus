# rubocop:disable Rails/NotNullColumn -- seguro: la tabla se trunca arriba antes de agregar
# estas columnas NOT NULL, así que no hay filas existentes que puedan violarlas.
class RestructureCadenceStepDefinitionsForCadenceDefinitions < ActiveRecord::Migration[7.1]
  def up
    # cadence_step_definitions y cadence_enrollments son de esta misma feature branch, sin
    # desplegar todavía a producción: las filas existentes son solo datos de desarrollo/prueba
    # (creadas por el rake de backfill legacy o specs corridas manualmente). Las limpiamos para
    # poder reestructurar la tabla sin arrastrar filas que ya no calzan con el nuevo esquema.
    execute 'TRUNCATE TABLE cadence_call_tasks, cadence_events, cadence_enrollments, cadence_step_definitions RESTART IDENTITY CASCADE'

    remove_index :cadence_step_definitions, name: 'idx_cadence_step_definitions_on_inbox_and_position'
    remove_index :cadence_step_definitions, name: 'idx_cadence_step_definitions_on_inbox_and_key'
    remove_index :cadence_step_definitions, name: 'index_cadence_step_definitions_on_account_id'
    remove_column :cadence_step_definitions, :account_id, :bigint
    remove_column :cadence_step_definitions, :inbox_id, :bigint

    add_column :cadence_step_definitions, :cadence_definition_id, :bigint, null: false
    add_index :cadence_step_definitions, %i[cadence_definition_id position], unique: true,
                                                                             name: 'idx_cadence_step_definitions_on_definition_and_position'
    add_index :cadence_step_definitions, %i[cadence_definition_id template_key], unique: true,
                                                                                 name: 'idx_cadence_step_definitions_on_definition_and_key'

    add_column :cadence_enrollments, :cadence_definition_id, :bigint, null: false
    add_index :cadence_enrollments, :cadence_definition_id
  end

  def down
    remove_index :cadence_enrollments, :cadence_definition_id
    remove_column :cadence_enrollments, :cadence_definition_id

    remove_index :cadence_step_definitions, name: 'idx_cadence_step_definitions_on_definition_and_position'
    remove_index :cadence_step_definitions, name: 'idx_cadence_step_definitions_on_definition_and_key'
    remove_column :cadence_step_definitions, :cadence_definition_id

    add_column :cadence_step_definitions, :inbox_id, :bigint, null: false
    add_column :cadence_step_definitions, :account_id, :bigint, null: false
    add_index :cadence_step_definitions, %i[inbox_id position], unique: true, name: 'idx_cadence_step_definitions_on_inbox_and_position'
    add_index :cadence_step_definitions, %i[inbox_id template_key], unique: true, name: 'idx_cadence_step_definitions_on_inbox_and_key'
    add_index :cadence_step_definitions, :account_id, name: 'index_cadence_step_definitions_on_account_id'
  end
end
# rubocop:enable Rails/NotNullColumn
