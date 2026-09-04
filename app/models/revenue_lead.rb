# Espejo analítico de un Zoho Lead. Ver RevenueIntelligence::LeadMapper para el mapeo de campos y
# RevenueIntelligence::BudgetParser para cómo se parsea presupuesto_raw en presupuesto_min/max.
#
# == Schema Information
#
# Table name: revenue_leads
#
#  id                 :bigint           not null, primary key
#  ad_account_name    :string
#  adset_name         :string
#  advert_name        :string
#  attempt_count      :integer          default(0), not null
#  campaign_name      :string
#  created_at_source  :datetime
#  desarrollo         :string
#  discard_reason     :string
#  estado_civil       :string
#  etapa_vida         :string
#  first_contact_at   :datetime
#  form_name          :string
#  genero             :string
#  lead_source        :string
#  lead_status        :string
#  nacionalidad       :string
#  ocupacion          :string
#  owner_name         :string
#  platform           :string
#  plazo              :string
#  presupuesto_max    :decimal(14, 2)
#  presupuesto_min    :decimal(14, 2)
#  presupuesto_raw    :string
#  qualified_at       :datetime
#  rango_edad         :string
#  raw_payload        :jsonb
#  razon_compra       :string
#  reassignment_count :integer          default(0), not null
#  synced_at          :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  ad_account_id      :string
#  adset_id           :string
#  advert_id          :string
#  campaign_id        :string
#  form_id            :string
#  owner_id           :string
#  revenue_contact_id :bigint
#  zoho_lead_id       :string           not null
#
# Indexes
#
#  index_revenue_leads_on_account_id_and_created_at_source   (account_id,created_at_source)
#  index_revenue_leads_on_account_id_and_desarrollo          (account_id,desarrollo)
#  index_revenue_leads_on_account_id_and_lead_status         (account_id,lead_status)
#  index_revenue_leads_on_account_id_and_owner_id            (account_id,owner_id)
#  index_revenue_leads_on_account_id_and_revenue_contact_id  (account_id,revenue_contact_id)
#  index_revenue_leads_on_account_id_and_zoho_lead_id        (account_id,zoho_lead_id) UNIQUE
#
class RevenueLead < ApplicationRecord
  belongs_to :account
  belongs_to :revenue_contact, optional: true
  has_many :revenue_deals, dependent: :nullify
  has_one :revenue_lead_journey, dependent: :destroy

  validates :zoho_lead_id, presence: true, uniqueness: { scope: :account_id }
end
