# == Schema Information
#
# Table name: cadence_step_definitions
#
#  id                    :bigint           not null, primary key
#  active                :boolean          default(TRUE), not null
#  body_variables        :jsonb            not null
#  creates_call_task     :boolean          default(FALSE), not null
#  day_offset            :integer
#  label                 :string
#  offset_minutes        :integer
#  position              :integer          not null
#  schedule_type         :string           not null
#  template_key          :string           not null
#  template_language     :string           default("es_MX"), not null
#  template_name         :string           not null
#  template_namespace    :string
#  time_of_day           :string
#  wait_window_minutes   :integer          not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  cadence_definition_id :bigint           not null
#
# Indexes
#
#  idx_cadence_step_definitions_on_definition_and_key       (cadence_definition_id,template_key) UNIQUE
#  idx_cadence_step_definitions_on_definition_and_position  (cadence_definition_id,position) UNIQUE
#
# Un paso de una CadenceDefinition: cuándo se dispara y a qué plantilla de Meta apunta. El
# adjunto multimedia del header (si la plantilla lo tiene) ya no se configura por paso: se
# resuelve en to_snapshot desde WhatsappTemplateInboxAssignment, que es la única fuente de
# verdad para el media_url de una plantilla en un inbox (Settings > Inbox > Configuration).
class CadenceStepDefinition < ApplicationRecord
  belongs_to :cadence_definition

  SCHEDULE_TYPES = %w[immediate offset_from_last_step day_offset_at_time].freeze
  MEDIA_TYPE_BY_HEADER_FORMAT = { 'IMAGE' => 'image', 'VIDEO' => 'video', 'DOCUMENT' => 'document' }.freeze

  validates :position, presence: true, numericality: { greater_than: 0 }
  validates :position, uniqueness: { scope: :cadence_definition_id }
  validates :template_key, presence: true, uniqueness: { scope: :cadence_definition_id }
  validates :template_name, presence: true
  validates :template_language, presence: true
  validates :schedule_type, inclusion: { in: SCHEDULE_TYPES }
  validates :wait_window_minutes, presence: true, numericality: { greater_than: 0 }
  validates :offset_minutes, presence: true, numericality: { greater_than: 0 },
                             if: -> { schedule_type == 'offset_from_last_step' }
  validates :time_of_day, presence: true, format: { with: /\A([01]\d|2[0-3]):[0-5]\d\z/ },
                          if: -> { schedule_type == 'day_offset_at_time' }
  validates :day_offset, presence: true, numericality: { greater_than_or_equal_to: 0 },
                         if: -> { schedule_type == 'day_offset_at_time' }

  scope :ordered, -> { order(:position) }

  # Congela el paso al momento de inscribir un lead (ver Cadences::StepsRepository): el
  # media_url/media_name/media_type resuelto aquí ya no cambia para ese enrollment aunque
  # el default del inbox se edite después.
  def to_snapshot
    as_json(only: %i[position template_key template_name template_language template_namespace
                     schedule_type offset_minutes day_offset time_of_day wait_window_minutes
                     creates_call_task body_variables])
      .merge(resolved_media_attributes)
  end

  private

  def resolved_media_attributes
    assignment = cadence_definition.inbox.whatsapp_template_inbox_assignments.find_by(template_name: template_name)
    return {} if assignment&.media_url.blank?

    {
      'media_url' => assignment.media_url,
      'media_name' => assignment.media_name,
      'media_type' => resolved_media_type
    }
  end

  def resolved_media_type
    header = registered_template&.dig('components')&.find { |c| c['type']&.upcase == 'HEADER' }
    MEDIA_TYPE_BY_HEADER_FORMAT[header&.dig('format')&.upcase]
  end

  def registered_template
    cadence_definition.inbox.channel.message_templates.find do |t|
      t['name'] == template_name && t['language']&.downcase == template_language.to_s.downcase
    end
  end
end
