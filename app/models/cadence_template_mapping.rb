# == Schema Information
#
# Table name: cadence_template_mappings
#
#  id           :bigint           not null, primary key
#  language      :string           default("es_MX"), not null
#  name          :string           not null
#  namespace     :string
#  template_key  :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  inbox_id      :bigint           not null
#
# Indexes
#
#  idx_cadence_template_mappings_on_inbox_and_key  (inbox_id,template_key) UNIQUE
#  index_cadence_template_mappings_on_account_id   (account_id)
#
# Override por inbox del mapeo template_key -> plantilla real de WhatsApp Business.
# Los template_key posibles son fijos (ver Cadences::StepDefinitions); esta tabla solo
# permite cambiar A CUAL plantilla de Meta apunta cada uno, nunca las reglas de tiempo/orden.
class CadenceTemplateMapping < ApplicationRecord
  belongs_to :account
  belongs_to :inbox

  TEMPLATE_KEYS = Cadences::StepDefinitions::STEPS.pluck(:template_key).freeze

  validates :template_key, presence: true, inclusion: { in: TEMPLATE_KEYS }
  validates :template_key, uniqueness: { scope: :inbox_id }
  validates :name, presence: true
  validates :language, presence: true
end
