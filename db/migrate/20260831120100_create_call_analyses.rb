class CreateCallAnalyses < ActiveRecord::Migration[7.1]
  def change
    create_table :call_analyses do |table|
      add_identity_columns(table)
      add_retry_columns(table)
      add_classification_columns(table)
      add_extraction_columns(table)
      add_traceability_columns(table)
      add_zoho_note_columns(table)

      table.timestamps
    end

    add_call_analysis_indexes
  end

  private

  def add_identity_columns(table)
    table.bigint :account_id, null: false
    table.bigint :call_id, null: false
    table.bigint :inbox_id, null: false
    table.bigint :agent_id
    table.string :provider_call_id, null: false
  end

  # Misma llave estable (call_id) en cada reintento, nunca duplica.
  def add_retry_columns(table)
    table.string :status, null: false, default: 'pending'
    table.string :error_step
    table.text :error_message
    table.integer :attempts, null: false, default: 0
    table.datetime :last_attempted_at
  end

  def add_classification_columns(table)
    table.string :role
    table.string :conversation_type
    table.string :confidence
    table.string :outcome_type
    table.datetime :outcome_at
    table.string :intent_level
  end

  def add_extraction_columns(table)
    table.jsonb :qualification_map, default: {}
    table.jsonb :objections, default: []
    table.jsonb :risks, default: []
    table.jsonb :evidence, default: {}
    table.jsonb :metrics, default: {}
    table.jsonb :scorecard, default: {}
    table.jsonb :llm_raw_response, default: {}
  end

  def add_traceability_columns(table)
    table.string :llm_model
    table.string :prompt_version
    table.string :scorecard_config_version
    table.datetime :analyzed_at
  end

  # Sub-estado independiente, reintentable sin reprocesar transcripción/LLM.
  def add_zoho_note_columns(table)
    table.string :zoho_note_status, null: false, default: 'not_applicable'
    table.string :zoho_note_id
    table.text :zoho_note_error
    table.string :zoho_deal_id
    table.string :zoho_deal_stage
  end

  def add_call_analysis_indexes
    add_index :call_analyses, :call_id, unique: true
    add_index :call_analyses, [:account_id, :status]
    add_index :call_analyses, [:account_id, :inbox_id, :analyzed_at]
    add_index :call_analyses, [:account_id, :agent_id, :analyzed_at]
    add_index :call_analyses, [:account_id, :role, :conversation_type]
  end
end
