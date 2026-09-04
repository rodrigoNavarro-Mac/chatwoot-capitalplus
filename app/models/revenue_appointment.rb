# Espejo de un Zoho Event (Meetings) real vinculado a un Lead/Deal. `verified` es siempre true en
# Fase 1 — toda fila nace de un Event real sincronizado, nunca de una señal débil como el Stage
# "Agendo cita - Videollamada" sin Event. Ver principio "no inventar evidencia" del módulo.
#
# == Schema Information
#
# Table name: revenue_appointments
#
#  id                 :bigint           not null, primary key
#  ends_at            :datetime
#  owner_name         :string
#  raw_payload        :jsonb
#  starts_at          :datetime
#  status             :string
#  subject            :string
#  synced_at          :datetime
#  verified           :boolean          default(TRUE), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  owner_id           :string
#  revenue_contact_id :bigint
#  revenue_deal_id    :bigint
#  zoho_deal_id       :string
#  zoho_event_id      :string           not null
#  zoho_lead_id       :string
#
# Indexes
#
#  idx_on_account_id_revenue_contact_id_1ef3ecfa59               (account_id,revenue_contact_id)
#  index_revenue_appointments_on_account_id_and_revenue_deal_id  (account_id,revenue_deal_id)
#  index_revenue_appointments_on_account_id_and_starts_at        (account_id,starts_at)
#  index_revenue_appointments_on_account_id_and_zoho_deal_id     (account_id,zoho_deal_id)
#  index_revenue_appointments_on_account_id_and_zoho_event_id    (account_id,zoho_event_id) UNIQUE
#
class RevenueAppointment < ApplicationRecord
  belongs_to :account
  belongs_to :revenue_contact, optional: true
  belongs_to :revenue_deal, optional: true

  validates :zoho_event_id, presence: true, uniqueness: { scope: :account_id }
end
