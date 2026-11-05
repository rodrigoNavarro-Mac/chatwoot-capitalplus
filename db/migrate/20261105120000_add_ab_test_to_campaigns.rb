# Prueba A/B de plantillas en campañas WhatsApp: la plantilla A sigue en campaigns.template_params;
# template_variant_b guarda la B ({ template_params:, message: }) y ab_split el % de la audiencia que
# recibe la A. Cada entrega registra qué variante recibió (nulo en campañas sin prueba A/B).
class AddAbTestToCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :campaigns, :template_variant_b, :jsonb
    add_column :campaigns, :ab_split, :integer, default: 50, null: false
    add_column :campaign_message_deliveries, :template_variant, :string
  end
end
