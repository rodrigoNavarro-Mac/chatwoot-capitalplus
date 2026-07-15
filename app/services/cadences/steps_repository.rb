# Fuente de verdad de la configuración VIVA de pasos de una CadenceDefinition (editable
# desde UI). Solo se consulta en Cadences::EnrollmentService#enroll!, para congelar un
# snapshot en el enrollment: el resto del motor de cadencia nunca vuelve a leer esta tabla,
# lee enrollment.steps_snapshot. Así, editar/reordenar/borrar pasos nunca afecta leads ya inscritos.
class Cadences::StepsRepository
  def self.snapshot_for(cadence_definition)
    cadence_definition.cadence_step_definitions.where(active: true).ordered.map(&:to_snapshot)
  end
end
