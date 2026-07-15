# Traduce la config legacy (Cadences::StepDefinitions::STEPS + cadence_template_mappings +
# config/cadences/template_mappings.yml) a una CadenceDefinition "default" con sus
# CadenceStepDefinition, una vez por inbox. Usado por el rake task
# cadences:backfill_step_definitions. Idempotente: no hace nada si el inbox ya tiene
# alguna CadenceDefinition configurada.
class Cadences::LegacyBackfillService
  pattr_initialize [:inbox!]

  def call
    return :skipped if inbox.cadence_definitions.exists?

    cadence_definition = create_default_cadence_definition!
    Cadences::StepDefinitions::STEPS.each { |legacy| create_step_definition!(cadence_definition, legacy) }
    :backfilled
  end

  private

  def create_default_cadence_definition!
    CadenceDefinition.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      name: 'Cadencia comercial (default)',
      is_default: true
    )
  end

  def create_step_definition!(cadence_definition, legacy)
    CadenceStepDefinition.create!(base_attributes(cadence_definition, legacy).merge(template_attributes(legacy)))
  end

  def base_attributes(cadence_definition, legacy)
    {
      cadence_definition_id: cadence_definition.id,
      position: legacy[:step],
      template_key: legacy[:template_key],
      schedule_type: schedule_type_for(legacy),
      offset_minutes: legacy[:offset]&./(60),
      day_offset: day_offset_for(legacy),
      time_of_day: legacy[:at],
      wait_window_minutes: legacy[:wait_window] / 60,
      creates_call_task: legacy[:creates_call_task]
    }
  end

  def template_attributes(legacy)
    mapping = CadenceTemplateMapping.find_by(inbox_id: inbox.id, template_key: legacy[:template_key])
    default = Cadences::TemplateResolver.mappings.dig('default', legacy[:template_key]) || {}

    {
      template_name: mapping&.name || default['name'],
      template_language: mapping&.language || default['language'] || 'es_MX',
      template_namespace: mapping&.namespace || default['namespace']
    }
  end

  def schedule_type_for(legacy)
    case legacy[:schedule]
    when :immediate then 'immediate'
    when :offset_from_enrollment then 'offset_from_last_step'
    when :next_day_at, :day_n_at then 'day_offset_at_time'
    end
  end

  def day_offset_for(legacy)
    case legacy[:schedule]
    when :next_day_at then 1
    when :day_n_at then legacy[:day] - 1
    end
  end
end
