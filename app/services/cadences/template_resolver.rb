# DEPRECADO: Cadences::StepExecutor ya no usa este resolver (resuelve la plantilla
# directo desde enrollment.steps_snapshot); sin llamadores en el motor de cadencia real.
#
# SIGUE VIVO A PROPÓSITO: Cadences::LegacyBackfillService lo usa (vía .mappings) para leer
# los defaults de config/cadences/template_mappings.yml al migrar los inboxes existentes.
# Borrar junto con CadenceTemplateMapping y Cadences::StepDefinitions una vez confirmado
# el backfill en producción.
#
# Traduce un template_key fijo (ver Cadences::StepDefinitions) a la plantilla real
# configurada para el inbox/proyecto, y resuelve sus variables liquid (nombre del
# contacto, etc.) reutilizando el motor de campañas ya existente.
class Cadences::TemplateResolver
  MAPPING_PATH = Rails.root.join('config/cadences/template_mappings.yml')
  PseudoCampaign = Struct.new(:sender, :inbox, :account)

  pattr_initialize [:template_key!, :conversation!]

  def resolve
    entry = mapping_for_key
    return if entry.blank?

    template_params = {
      'name' => entry['name'],
      'language' => entry['language'],
      'namespace' => entry['namespace'],
      'processed_params' => entry['processed_params'] || {}
    }

    Whatsapp::LiquidTemplateProcessorService.new(campaign: pseudo_campaign, contact: contact).process_template_params(template_params)
  end

  def self.mappings
    @mappings ||= YAML.load_file(MAPPING_PATH)
  end

  private

  delegate :inbox, :account, :contact, to: :conversation

  def pseudo_campaign
    PseudoCampaign.new(conversation.assignee, inbox, account)
  end

  def mapping_for_key
    db_override_mapping || self.class.mappings.dig('inboxes', inbox.id.to_s, template_key) || self.class.mappings.dig('default', template_key)
  end

  def db_override_mapping
    override = CadenceTemplateMapping.find_by(inbox_id: inbox.id, template_key: template_key)
    return if override.blank?

    { 'name' => override.name, 'language' => override.language, 'namespace' => override.namespace }.compact
  end
end
