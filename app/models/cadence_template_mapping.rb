# == Schema Information
#
# Table name: cadence_template_mappings
#
#  id           :bigint           not null, primary key
#  language     :string           default("es_MX"), not null
#  name         :string           not null
#  namespace    :string
#  template_key :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  inbox_id     :bigint           not null
#
# Indexes
#
#  idx_cadence_template_mappings_on_inbox_and_key  (inbox_id,template_key) UNIQUE
#  index_cadence_template_mappings_on_account_id   (account_id)
#
# DEPRECADO: reemplazado por CadenceStepDefinition, que fusiona esta tabla con los pasos
# fijos de Cadences::StepDefinitions y agrega horario/adjunto editables por paso. El motor
# de cadencia (EnrollmentService, StepExecutor, etc.) ya no lee este modelo.
#
# SIGUE VIVO A PROPÓSITO: Cadences::LegacyBackfillService lo usa para leer los overrides de
# plantilla por inbox que ya existen en producción (chat.capitalplus.mx) y migrarlos a
# CadenceStepDefinition la primera vez que corra el rake cadences:backfill_step_definitions
# contra esa base. Una vez confirmado ese backfill en producción, este modelo (y su tabla,
# vía una migración de drop_table) se puede borrar sin pérdida de datos.
class CadenceTemplateMapping < ApplicationRecord
  belongs_to :account
  belongs_to :inbox

  TEMPLATE_KEYS = Cadences::StepDefinitions::STEPS.pluck(:template_key).freeze

  validates :template_key, presence: true, inclusion: { in: TEMPLATE_KEYS }
  validates :template_key, uniqueness: { scope: :inbox_id }
  validates :name, presence: true
  validates :language, presence: true
end
