# Traduce las filas crudas de RevenueIntelligence::Zoho::StageHistoryClient#list a atributos de
# RevenueStageEvent. Puro — no toca la base de datos.
#
# Cada fila de Zoho representa una etapa YA CERRADA (o la actual, si Moved_To__s/
# Stage_Duration_Calendar_Days vienen null): "el deal estuvo en `Stage` y se movió a
# `Moved_To__s`". `entered_at` de una fila se deriva del `Modified_Time` de la fila ANTERIOR
# (cuando esa fila anterior se cerró, esta empezó) — para la primera fila se usa
# `fallback_entered_at` (normalmente el Created_Time del propio deal). `duration_seconds` se toma
# directo de `Stage_Duration_Calendar_Days` (ya calculado por Zoho) en vez de recalcularlo a mano:
# una comprobación contra datos reales mostró que Modified_Time - duration no siempre cuadra
# exacto con el Modified_Time de la fila anterior, así que no se intenta reconciliar por resta.
class RevenueIntelligence::StageHistoryBuilder
  SECONDS_PER_DAY = 86_400

  def self.build(rows, fallback_entered_at:)
    new(rows, fallback_entered_at).build
  end

  def initialize(rows, fallback_entered_at)
    @rows = sort(rows)
    @fallback_entered_at = fallback_entered_at
  end

  def build
    rows.each_with_index.map { |row, index| build_row(row, index) }
  end

  private

  attr_reader :rows, :fallback_entered_at

  def sort(rows)
    Array(rows).sort_by { |row| row['Modified_Time'].to_s }
  end

  def build_row(row, index)
    previous_row = rows[index - 1] if index.positive?
    # La fila actual/abierta también trae Modified_Time (se actualiza aunque no haya "salido" de
    # la etapa) — Moved_To__s es la señal real de si esta fila ya cerró o sigue activa.
    closed = row['Moved_To__s'].present?

    {
      zoho_history_id: row['id'],
      stage: row['Stage'],
      previous_stage: previous_row&.dig('Stage'),
      entered_at: entered_at_for(previous_row),
      exited_at: closed ? parse_time(row['Modified_Time']) : nil,
      duration_seconds: closed ? duration_seconds_for(row) : nil,
      raw_payload: row
    }
  end

  def entered_at_for(previous_row)
    return parse_time(previous_row['Modified_Time']) if previous_row

    fallback_entered_at
  end

  def duration_seconds_for(row)
    days = row['Stage_Duration_Calendar_Days']
    return nil if days.blank?

    (days.to_f * SECONDS_PER_DAY).round
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
