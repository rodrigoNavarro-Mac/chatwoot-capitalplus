# Calcula, de forma determinística en Ruby (no LLM), las métricas de conversación que el spec de
# análisis de llamadas pide como "verdad objetiva": talk ratio, monólogo más largo, número de
# preguntas abiertas/cerradas, uso de CTA. Recibe `call.transcript_segments` ya normalizados
# (speaker/start_seconds/end_seconds/text, ver Crm::Aircall::Api::TranscriptionClient) más los
# labels de hablante que corresponden al agente (puede haber más de uno en una llamada
# transferida), para poder separar "agente" de "externo" sin depender de que el LLM lo adivine.
#
# El resultado se guarda en call_analyses.metrics, separado de llm_raw_response, para que quede
# auditable qué es cálculo exacto y qué es interpretación del modelo.
class Voice::ConversationMetricsCalculator
  OPEN_QUESTION_WORDS = %w[qué como cómo cuando cuándo donde dónde
                           por cual cuál quien quién cuanto cuánto cuanta cuánta].freeze
  CTA_KEYWORDS = ['te agendo', 'te mando', 'te comparto', 'te envío', 'firmamos', 'apartamos',
                  'agendamos', 'reservamos', 'confirmamos la cita', 'te paso'].freeze

  def initialize(segments:, agent_speaker_labels:)
    @agent_speaker_labels = Array(agent_speaker_labels).map(&:to_s)
    @segments = normalize(segments)
  end

  def calculate
    return empty_result if segments.blank?

    {
      talk_ratio: talk_ratio,
      longest_monologue_seconds: longest_monologue_seconds,
      questions: questions_count,
      cta_used: cta_used?,
      total_duration_seconds: total_duration_seconds
    }
  end

  private

  attr_reader :segments, :agent_speaker_labels

  def empty_result
    { talk_ratio: nil, longest_monologue_seconds: 0, questions: { open: 0, closed: 0 }, cta_used: false, total_duration_seconds: 0 }
  end

  # Normaliza símbolos/strings indistintamente (los segmentos vienen de un jsonb, con claves
  # string) y rellena end_seconds ausentes con el start_seconds del siguiente segmento — Aircall
  # AI no siempre manda end_time por utterance.
  def normalize(raw_segments)
    sorted = raw_segments.to_a.map(&:with_indifferent_access).sort_by { |s| s[:start_seconds].to_i }

    sorted.each_with_index.map do |segment, index|
      next_start = sorted[index + 1]&.dig(:start_seconds)
      end_seconds = segment[:end_seconds].presence || next_start || segment[:start_seconds].to_i
      {
        speaker: segment[:speaker].to_s,
        agent: agent_speaker?(segment[:speaker].to_s),
        start_seconds: segment[:start_seconds].to_i,
        end_seconds: end_seconds.to_i,
        text: segment[:text].to_s
      }
    end
  end

  def agent_speaker?(speaker)
    agent_speaker_labels.include?(speaker)
  end

  def duration(segment)
    [(segment[:end_seconds] - segment[:start_seconds]), 0].max
  end

  def total_duration_seconds
    return 0 if segments.blank?

    segments.last[:end_seconds] - segments.first[:start_seconds]
  end

  def talk_ratio
    total = total_duration_seconds
    return nil if total.zero?

    agent_seconds = segments.select { |s| s[:agent] }.sum { |s| duration(s) }
    (agent_seconds.to_f / total).round(2)
  end

  def longest_monologue_seconds
    longest = 0
    current_speaker = nil
    current_run = 0

    segments.each do |segment|
      if segment[:speaker] == current_speaker
        current_run += duration(segment)
      else
        current_speaker = segment[:speaker]
        current_run = duration(segment)
      end
      longest = [longest, current_run].max
    end

    longest
  end

  # Heurística por regex — imperfecta a propósito (ver comentario de clase), el prompt del LLM
  # puede complementarla citando evidencia, pero el conteo base siempre viene de aquí.
  def questions_count
    open = 0
    closed = 0

    segments.each do |segment|
      segment[:text].scan(/¿([^?¿]+)\?/).each do |(question)|
        first_word = question.strip.split(/\s+/).first.to_s.downcase
        first_word.in?(OPEN_QUESTION_WORDS) ? open += 1 : closed += 1
      end
    end

    { open: open, closed: closed }
  end

  def cta_used?
    full_text = segments.select { |s| s[:agent] }.map { |s| s[:text].downcase }.join(' ')
    CTA_KEYWORDS.any? { |keyword| full_text.include?(keyword) }
  end
end
