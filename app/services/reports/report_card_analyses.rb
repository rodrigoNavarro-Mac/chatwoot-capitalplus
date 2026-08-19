# Acceso al mini-análisis de IA por card (Reports::WeeklyOpsAnalysisLlmService::CARD_KEYS),
# compartido entre Reports::WeeklyOpsReportPdfService y Reports::WeeklyOpsReportDocxService — cada
# uno decide cómo renderizarlo (Prawn vs OOXML), pero ambos necesitan lo mismo: el texto (si existe)
# para una key dada.
module Reports::ReportCardAnalyses
  def card_analysis(key)
    return nil if key.blank?

    (report.card_analyses || {})[key.to_s].presence
  end
end
