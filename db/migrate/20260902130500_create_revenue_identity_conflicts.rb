# Bitácora de conflictos que RevenueIntelligence::IdentityResolver NO resuelve automáticamente
# (ej. un teléfono que apunta a dos revenue_contacts distintos, o un intento de sobrescribir un
# campo no-nulo con un valor distinto). El resolver nunca fusiona silenciosamente ni sobrescribe
# — cualquier ambigüedad queda aquí como deuda de revisión manual explícita.
class CreateRevenueIdentityConflicts < ActiveRecord::Migration[7.1]
  def change
    create_table :revenue_identity_conflicts do |table|
      table.bigint :account_id, null: false
      table.string :conflict_type, null: false # phone_multiple_contacts / field_mismatch / etc.
      table.string :match_key # el phone/email normalizado que disparó el conflicto
      table.jsonb :candidate_ids, default: [] # revenue_contacts.id candidatos, no fusionados
      table.string :source # job/servicio que lo detectó
      table.boolean :resolved, null: false, default: false
      table.datetime :resolved_at
      table.jsonb :raw_context, default: {}

      table.timestamps
    end

    add_index :revenue_identity_conflicts, [:account_id, :resolved]
    add_index :revenue_identity_conflicts, [:account_id, :conflict_type]
  end
end
