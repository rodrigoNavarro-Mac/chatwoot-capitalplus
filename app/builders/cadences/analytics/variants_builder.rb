# Compara el desempeño de cada CadenceDefinition (variante) de un inbox lado a lado —
# el reporte central para leer un A/B/N test de "razon_compra". A propósito NO reusa
# BaseBuilder#enrollment_scope: ese scope aplica filter_by_cadence_definition_id si el
# admin tiene una variante seleccionada en el filtro general, lo cual dejaría esta tabla
# con una sola fila. Aquí siempre se muestran todas las variantes del inbox filtrado.
class Cadences::Analytics::VariantsBuilder < Cadences::Analytics::BaseBuilder
  def build
    definitions_scope.map { |definition| variant_metrics(definition) }
  end

  private

  def definitions_scope
    scope = account.cadence_definitions.active
    scope = scope.for_inbox(filters[:inbox_id]) if filters[:inbox_id].present?
    scope.order(:id)
  end

  def base_scope
    account.cadence_enrollments
           .filter_by_date_range(filters[:range])
           .filter_by_inbox_id(filters[:inbox_id])
           .filter_by_assignee_id(filters[:assignee_id])
           .filter_by_team_id(filters[:team_id])
           .filter_by_status(filters[:status])
           .filter_by_step(filters[:step])
  end

  def variant_metrics(definition)
    scope = base_scope.where(cadence_definition_id: definition.id)
    leads = scope.count
    responded = scope.where(status: RESPONDED_STATUSES).count

    {
      id: definition.id,
      name: definition.name,
      segment_value: definition.segment_value,
      is_default: definition.is_default,
      leads_in_cadence: leads,
      responded_count: responded,
      response_rate: safe_rate(responded, leads),
      recovered_count: scope.recovered.count,
      cold_count: scope.cold.count
    }
  end
end
