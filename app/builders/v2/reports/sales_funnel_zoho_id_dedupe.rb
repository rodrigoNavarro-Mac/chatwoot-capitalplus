# Dos contactos de Chatwoot distintos pueden terminar vinculados al MISMO zoho_id (ej. el mismo
# cliente escribió desde dos números/formatos que nunca se fusionaron en Chatwoot) — sin este
# dedupe, V2::Reports::SalesFunnelBuilder contaba el mismo lead de Zoho dos veces en "leads" (caso
# real detectado 2026-09-03). Separada de esa clase solo por tamaño, mismo criterio que
# SalesFunnelDealActivity/SalesFunnelReactivatedLeads.
class V2::Reports::SalesFunnelZohoIdDedupe
  # Se conserva, por cada zoho_id repetido, el par con el conversation_id más chico — al ser un id
  # autoincremental de Postgres, equivale a la conversación más antigua sin necesitar otra consulta
  # por created_at.
  def dedupe(pairs)
    return pairs if pairs.size < 2

    zoho_id_by_contact = Contact.where(id: pairs.map(&:last))
                                .pluck(:id, Arel.sql("additional_attributes -> 'external' ->> 'zoho_id'"))
                                .to_h

    pairs.group_by { |(_conversation_id, contact_id)| zoho_id_by_contact[contact_id] }
         .values
         .map { |group| group.min_by(&:first) }
  end
end
