class MigrateCadenceStepMediaToInboxAssignments < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  # Antes de quitar media_url/media_type/media_name de cadence_step_definitions (ver
  # migracion siguiente), copiamos cualquier valor ya configurado hacia
  # whatsapp_template_inbox_assignments, que pasa a ser la unica fuente de verdad. Si el
  # inbox ya tenia un default distinto para esa plantilla, no lo pisamos (se asume
  # intencional) pero lo reportamos para revision manual.
  def up
    CadenceStepDefinition.where.not(media_url: [nil, '']).find_each do |step|
      cadence_definition = step.cadence_definition
      next if cadence_definition.blank?

      assignment = WhatsappTemplateInboxAssignment.find_or_initialize_by(
        account_id: cadence_definition.account_id,
        inbox_id: cadence_definition.inbox_id,
        template_name: step.template_name
      )

      if assignment.new_record?
        assignment.media_url = step.media_url
        assignment.media_name = step.media_name
        assignment.save!
      elsif assignment.media_url != step.media_url
        say "CONFLICTO: inbox_id=#{cadence_definition.inbox_id} template=#{step.template_name} " \
            "ya tiene media_url=#{assignment.media_url.inspect} en whatsapp_template_inbox_assignments, " \
            "distinto al del step #{step.id} (#{step.media_url.inspect}). No se sobreescribio, revisar a mano."
      end
    end
  end

  def down
    # No-op: no hay forma segura de distinguir que assignments vinieron de este backfill.
  end
end
