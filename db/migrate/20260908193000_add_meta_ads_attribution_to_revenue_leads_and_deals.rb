# Agrega 5 campos de Zoho Leads que faltaban (Social Lead ID, Lead Type, Page Id/Name, Canal de
# calificación — confirmados contra la cuenta real vía la API de Zoho) y, más importante, COPIA el
# set completo de atribución de Meta Ads del Lead hacia el Deal en el momento en que se vinculan
# (ver RevenueIntelligence::LeadMapper / SyncZohoLeadsJob#link_converted_deal /
# Api::V2::Accounts::RevenueIntelligenceController#relink_deal, todos actualizados junto con esta
# migración) — Zoho NUNCA guarda estos campos en el propio Deal (confirmado vía Zoho::getFields:
# el módulo Deals solo trae Lead_Source/Campaign_Source), así que sin esta copia la atribución de
# marketing se pierde para siempre en cuanto un Lead se convierte, si el vínculo revenue_lead_id
# llegara a romperse o el Lead se purgara en Zoho.
class AddMetaAdsAttributionToRevenueLeadsAndDeals < ActiveRecord::Migration[7.1]
  def change
    add_lead_columns
    add_deal_columns
  end

  private

  def add_lead_columns
    change_table :revenue_leads, bulk: true do |t|
      t.string :social_lead_id
      t.string :lead_type
      t.string :page_id
      t.string :page_name
      t.string :qualification_channel
    end
  end

  def add_deal_columns
    change_table :revenue_deals, bulk: true do |t|
      t.string :campaign_id
      t.string :campaign_name
      t.string :adset_id
      t.string :adset_name
      t.string :advert_id
      t.string :advert_name
      t.string :ad_account_id
      t.string :ad_account_name
      t.string :form_id
      t.string :form_name
      t.string :page_id
      t.string :page_name
      t.string :social_lead_id
      t.string :lead_type
      t.string :platform
      t.string :qualification_channel
    end
  end
end
