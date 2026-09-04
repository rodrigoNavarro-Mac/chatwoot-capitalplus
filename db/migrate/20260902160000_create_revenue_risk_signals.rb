# Señales con estado (abierta/resuelta) sobre reglas determinísticas de negocio ('risk') y de
# integridad del propio CRM ('data_quality') — ver RevenueIntelligence::RiskSignalRecorder y el
# plan de Fase 4. A diferencia de revenue_rollups (aditiva, Fase 3), estas filas se CIERRAN solas
# cuando la condición que las generó deja de cumplirse — por eso el índice único es parcial
# (solo sobre filas abiertas): permite reabrir la misma señal más adelante sin perder el historial
# de la anterior.
class CreateRevenueRiskSignals < ActiveRecord::Migration[7.1]
  def change
    create_table :revenue_risk_signals do |table|
      table.bigint :account_id, null: false
      table.string :category, null: false     # 'risk' | 'data_quality'
      table.string :signal_type, null: false
      table.string :subject_type, null: false  # 'RevenueDeal' | 'RevenueLead' | 'RevenueAppointment' | 'RevenueIdentityConflict'
      table.bigint :subject_id, null: false
      table.string :severity, null: false, default: 'medium' # 'low' | 'medium' | 'high'
      table.datetime :first_detected_at, null: false          # fijo, no se mueve entre re-detecciones
      table.datetime :detected_at, null: false                 # última corrida que confirmó la señal activa
      table.datetime :resolved_at
      table.jsonb :context, default: {}

      table.timestamps
    end

    add_index :revenue_risk_signals, [:account_id, :category, :signal_type, :subject_type, :subject_id],
              unique: true, where: 'resolved_at IS NULL', name: 'idx_revenue_risk_signals_open_dedup'
    add_index :revenue_risk_signals, [:account_id, :category, :resolved_at]
    add_index :revenue_risk_signals, [:account_id, :signal_type]
  end
end
