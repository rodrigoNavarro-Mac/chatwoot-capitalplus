# Ancla de identidad de Revenue Intelligence: una fila por persona real, resuelta por
# RevenueIntelligence::IdentityResolver a partir de teléfono/email/ids de Zoho. Tabla nueva y
# separada de `contacts` a propósito (ver AGENTS de arquitectura del proyecto): el resolver nunca
# escribe en `contacts`, solo lee de ahí. Los 4 índices únicos parciales son el mecanismo real de
# idempotencia bajo reintentos concurrentes del job de resolución.
class CreateRevenueContacts < ActiveRecord::Migration[7.1]
  def change
    create_table :revenue_contacts do |table|
      add_identity_columns(table)
      add_zoho_link_columns(table)
      add_lifecycle_columns(table)

      table.timestamps
    end

    add_revenue_contact_indexes
  end

  private

  def add_identity_columns(table)
    table.bigint :account_id, null: false
    table.string :normalized_phone   # E.164 vía TelephoneNumber; null si no se pudo parsear
    table.string :raw_phone          # valor original, nunca se destruye
    table.string :email
    table.bigint :chatwoot_contact_id # lógico -> contacts.id, solo lectura, nunca se escribe ahí
  end

  # Strings (no bigint): Zoho documenta sus record ids como string, aunque numéricos.
  def add_zoho_link_columns(table)
    table.string :zoho_lead_id
    table.string :zoho_contact_id
    # "deal más reciente" de conveniencia — la fuente de verdad de TODOS los deals de un contacto
    # es revenue_deals.revenue_contact_id, no esta columna.
    table.string :zoho_deal_id
  end

  def add_lifecycle_columns(table)
    table.datetime :first_seen_at, null: false
    table.datetime :last_seen_at, null: false
  end

  def add_revenue_contact_indexes
    add_index :revenue_contacts, [:account_id, :normalized_phone],
              **partial_unique('normalized_phone', 'idx_revenue_contacts_on_account_phone')
    add_index :revenue_contacts, [:account_id, :zoho_lead_id],
              **partial_unique('zoho_lead_id', 'idx_revenue_contacts_on_account_zoho_lead')
    add_index :revenue_contacts, [:account_id, :zoho_contact_id],
              **partial_unique('zoho_contact_id', 'idx_revenue_contacts_on_account_zoho_contact')
    add_index :revenue_contacts, [:account_id, :chatwoot_contact_id],
              **partial_unique('chatwoot_contact_id', 'idx_revenue_contacts_on_account_cw_contact')
    add_index :revenue_contacts, [:account_id, :email]
  end

  # Único parcial: solo aplica cuando la columna no es null — permite N filas con esa columna en
  # null (identidad todavía no resuelta) sin violar el índice único.
  def partial_unique(column, index_name)
    { unique: true, where: "#{column} IS NOT NULL", name: index_name }
  end
end
