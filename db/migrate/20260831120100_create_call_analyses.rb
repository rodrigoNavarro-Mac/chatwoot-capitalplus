class CreateCallAnalyses < ActiveRecord::Migration[7.1]
  def change
    create_table :call_analyses do |t|
      t.bigint :account_id, null: false
      t.bigint :call_id, null: false
      t.bigint :inbox_id, null: false
      t.bigint :agent_id
      t.string :provider_call_id, null: false

      # Estado/reintento — misma llave estable (call_id) en cada reintento, nunca duplica.
      t.string :status, null: false, default: 'pending'
      t.string :error_step
      t.text :error_message
      t.integer :attempts, null: false, default: 0
      t.datetime :last_attempted_at

      # Clasificación
      t.string :role
      t.string :conversation_type
      t.string :confidence
      t.string :outcome_type
      t.datetime :outcome_at
      t.string :intent_level

      # Extracción estructurada
      t.jsonb :qualification_map, default: {}
      t.jsonb :objections, default: []
      t.jsonb :risks, default: []
      t.jsonb :evidence, default: {}
      t.jsonb :metrics, default: {}
      t.jsonb :scorecard, default: {}
      t.jsonb :llm_raw_response, default: {}

      # Trazabilidad
      t.string :llm_model
      t.string :prompt_version
      t.string :scorecard_config_version
      t.datetime :analyzed_at

      # Nota en Zoho — sub-estado independiente, reintentable sin reprocesar transcripción/LLM.
      t.string :zoho_note_status, null: false, default: 'not_applicable'
      t.string :zoho_note_id
      t.text :zoho_note_error
      t.string :zoho_deal_id
      t.string :zoho_deal_stage

      t.timestamps
    end

    add_call_analysis_indexes
  end

  private

  def add_call_analysis_indexes
    add_index :call_analyses, :call_id, unique: true
    add_index :call_analyses, [:account_id, :status]
    add_index :call_analyses, [:account_id, :inbox_id, :analyzed_at]
    add_index :call_analyses, [:account_id, :agent_id, :analyzed_at]
    add_index :call_analyses, [:account_id, :role, :conversation_type]
  end
end
