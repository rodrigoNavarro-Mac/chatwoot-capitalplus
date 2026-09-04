# Espejo analítico 1:1 de call_analyses, aplanando su jsonb (qualification_map/scorecard/metrics)
# a columnas planas — para que Fase 3 (agregados) no tenga que parsear jsonb en cada corrida.
# Poblada por RevenueIntelligence::ExtractCallFeaturesJob. Conserva los jsonb originales en
# call_analyses intactos — esta tabla es una PROYECCIÓN, nunca la fuente de verdad.
class CreateRevenueCallFeatures < ActiveRecord::Migration[7.1]
  def change
    create_table :revenue_call_features do |table|
      add_identity_columns(table)
      add_classification_columns(table)
      add_scorecard_columns(table)
      add_metric_columns(table)
      add_qualification_columns(table)

      table.timestamps
    end

    add_revenue_call_feature_indexes
  end

  private

  def add_identity_columns(table)
    table.bigint :account_id, null: false
    table.bigint :call_id, null: false           # lógico -> calls.id
    table.bigint :call_analysis_id, null: false   # lógico -> call_analyses.id
    table.bigint :revenue_contact_id
    table.string :zoho_deal_id
    table.bigint :agent_id
    table.datetime :started_at
  end

  def add_classification_columns(table)
    table.string :role
    table.string :conversation_type
    table.string :intent_level
    table.string :confidence
    table.string :outcome_type
    table.datetime :outcome_at
  end

  def add_scorecard_columns(table)
    table.decimal :score_total, precision: 6, scale: 2
    table.string :score_reading
  end

  def add_metric_columns(table)
    table.decimal :talk_ratio, precision: 5, scale: 4
    table.integer :longest_monologue_seconds
    table.integer :open_questions, null: false, default: 0
    table.integer :closed_questions, null: false, default: 0
    table.boolean :cta_used, null: false, default: false
    table.integer :qualification_count, null: false, default: 0
    table.integer :objection_count, null: false, default: 0
    table.integer :risk_count, null: false, default: 0
    table.decimal :qualification_completeness, precision: 5, scale: 4
  end

  # Las 10 claves cerradas de qualification_map (QUALIFICATION_KEYS en
  # CallAnalysis::StructuredAnalysisLlmService) como columnas booleanas, para filtrar/agrupar sin
  # tocar jsonb.
  def add_qualification_columns(table)
    table.boolean :qual_intencion_vivir_invertir, null: false, default: false
    table.boolean :qual_necesidad_concreta, null: false, default: false
    table.boolean :qual_requisito_indispensable, null: false, default: false
    table.boolean :qual_presupuesto, null: false, default: false
    table.boolean :qual_forma_pago_credito, null: false, default: false
    table.boolean :qual_momento_compra, null: false, default: false
    table.boolean :qual_tomadores_decision, null: false, default: false
    table.boolean :qual_alternativas_competencia, null: false, default: false
    table.boolean :qual_bloqueo_principal, null: false, default: false
    table.boolean :qual_siguiente_paso, null: false, default: false
  end

  def add_revenue_call_feature_indexes
    add_index :revenue_call_features, [:account_id, :call_id], unique: true
    add_index :revenue_call_features, [:account_id, :revenue_contact_id]
    add_index :revenue_call_features, [:account_id, :agent_id, :started_at]
    add_index :revenue_call_features, [:account_id, :outcome_type]
    add_index :revenue_call_features, [:account_id, :intent_level]
  end
end
