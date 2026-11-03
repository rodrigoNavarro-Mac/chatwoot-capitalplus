# Motivo por el que una campaña WhatsApp se pausó sola (Campaigns::AutoPauseService), p. ej.
# "meta_error:131031" o "number_health:RED/CONNECTED". Nulo cuando la pausa fue manual.
class AddPauseReasonToCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :campaigns, :pause_reason, :string
  end
end
