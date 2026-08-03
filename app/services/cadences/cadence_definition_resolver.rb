# Decide qué CadenceDefinition debe usarse para inscribir una conversación:
# 1. Resuelve el segmento (razon_compra) vía Cadences::RazonCompraResolver.
# 2. Si hay CadenceDefinition activas del inbox que matcheen ese segmento, reparte el lead
#    entre ellas por conteo (asigna la que hasta ahora tiene menos enrollments) — así se
#    logra el reparto "1 y 1" de un A/B/N test sin depender de un contador aparte que se
#    pueda desincronizar.
# 3. Si no hay match (segmento vacío o ninguna CadenceDefinition configurada para ese
#    valor), aplica el mismo reparto 1 y 1 entre todas las CadenceDefinition activas del
#    inbox que no tengan segment_value configurado (catch-all) — así varias cadencias
#    activas sin segmento (p. ej. is_default + otra más) también se reparten los leads en
#    vez de que todo caiga siempre en la marcada is_default.
# 4. Si tampoco hay ninguna catch-all activa, usa la marcada is_default para el inbox,
#    si existe (failsafe por si alguna vez hay un default con segment_value configurado).
class Cadences::CadenceDefinitionResolver
  pattr_initialize [:conversation!]

  def resolve
    matching = matching_definitions
    return least_used(matching) if matching.any?

    catch_all = catch_all_definitions
    return least_used(catch_all) if catch_all.any?

    default_definition
  end

  private

  def matching_definitions
    segment_value = Cadences::RazonCompraResolver.new(conversation: conversation).resolve
    return [] if segment_value.blank?

    CadenceDefinition.active.for_inbox(conversation.inbox_id).matching_segment(segment_value).to_a
  end

  def catch_all_definitions
    CadenceDefinition.active.for_inbox(conversation.inbox_id).without_segment.to_a
  end

  def least_used(candidates)
    ids = candidates.map(&:id)
    counts = CadenceEnrollment.where(cadence_definition_id: ids).group(:cadence_definition_id).count
    least_used_id = ids.min_by { |id| counts[id] || 0 }
    candidates.find { |definition| definition.id == least_used_id }
  end

  def default_definition
    CadenceDefinition.active.for_inbox(conversation.inbox_id).find_by(is_default: true)
  end
end
