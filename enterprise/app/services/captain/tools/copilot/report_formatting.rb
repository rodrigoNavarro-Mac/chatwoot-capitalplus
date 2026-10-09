# Helpers de formateo de texto compartidos por los tools de Copilot que leen informes
# administrativos (Revenue Intelligence / Weekly Ops Report). Evita repetir en cada tool la misma
# lógica de "lista vacía" y de formatear porcentajes/listas como texto plano para el LLM --
# `execute` siempre debe devolver un string, nunca un hash/JSON (mismo contrato que el resto de
# tools de Copilot, ver search_contacts_service.rb).
module Captain::Tools::Copilot::ReportFormatting
  private

  def not_found_message(entity_label)
    "No #{entity_label} found"
  end

  def format_percent(value)
    return 'N/A' if value.nil?

    "#{value.round(1)}%"
  end

  def format_rows(rows, &)
    rows.map(&).join("\n---\n")
  end
end
