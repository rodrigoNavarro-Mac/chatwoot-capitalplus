# Parser heurístico del campo `Presupuesto` de Zoho Leads (texto libre, sin formato — confirmado
# contra el field real de esta cuenta: data_type "text", no currency). NUNCA se le pide certeza:
# el valor original siempre se conserva aparte (revenue_leads.presupuesto_raw); esto solo intenta
# extraer un rango numérico best-effort para filtros/analítica. Casos ambiguos o sin ningún número
# reconocible devuelven {min: nil, max: nil} — no es un bug, es la naturaleza de la fuente.
#
# Reglas (ver definición exacta en el plan de Fase 1, sección "Campos derivados"):
#   - Normaliza: minúsculas, quita "$"/"mxn"/"usd"/comas de miles.
#   - Multiplicadores reconocidos: mdp/millon(es)/mill -> x1,000,000; mil/k -> x1,000.
#   - 2 números reconocibles -> min = el menor, max = el mayor (sin asumir orden de aparición).
#   - 1 número + calificador "hasta"/"menos" -> solo max. + "desde"/"a partir" -> solo min.
#   - 1 número sin calificador -> se toma como estimado puntual (min = max).
#   - 0 números reconocibles -> ambos nil (ej. "no tiene", "por definir").
class RevenueIntelligence::BudgetParser
  MULTIPLIERS = {
    'mdp' => 1_000_000, 'millones' => 1_000_000, 'millon' => 1_000_000, 'mill' => 1_000_000,
    'mil' => 1_000, 'k' => 1_000
  }.freeze

  UP_TO_WORDS = %w[hasta menos].freeze
  FROM_WORDS = %w[desde partir].freeze

  TOKEN_PATTERN = /(\d+(?:[.,]\d+)?)\s*(mdp|millones|millon|mill|mil|k)?/

  def self.parse(raw)
    new(raw).parse
  end

  def initialize(raw)
    @raw = raw.to_s
  end

  def parse
    return { min: nil, max: nil } if raw.blank?

    values = extract_values(normalized)
    case values.size
    when 0 then { min: nil, max: nil }
    when 1 then single_value_result(values.first)
    else { min: values.min, max: values.max }
    end
  end

  private

  attr_reader :raw

  # Comas tratadas como separador de miles (convención dominante en México: "1,200,000.50"), no
  # como decimal — una ambigüedad de locale inherente a texto libre, aceptada a propósito.
  def normalized
    raw.downcase.gsub(/[$,]/, '').gsub(/\bmxn\b|\busd\b/, '')
  end

  def extract_values(text)
    text.scan(TOKEN_PATTERN).filter_map do |number, unit|
      value = number.tr(',', '.').to_f * (MULTIPLIERS[unit] || 1)
      value.round(2) unless value.zero?
    end
  end

  def single_value_result(value)
    if UP_TO_WORDS.any? { |word| normalized.include?(word) }
      { min: nil, max: value }
    elsif FROM_WORDS.any? { |word| normalized.include?(word) }
      { min: value, max: nil }
    else
      { min: value, max: value }
    end
  end
end
