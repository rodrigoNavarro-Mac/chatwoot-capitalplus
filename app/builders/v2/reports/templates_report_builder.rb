# Compara el rendimiento entre plantillas de WhatsApp (enviados/entregados/leídos/contestados),
# sin importar si la plantilla se mandó vía la bienvenida automática de Zoho CRM o un paso de
# Cadencia — ambos flujos dejan el mismo rastro en Message#additional_attributes.template_params,
# así que no hace falta cruzar CadenceEvent ni CampaignMessageDelivery para esta comparación.
class V2::Reports::TemplatesReportBuilder
  include DateRangeHelper

  TEMPLATE_NAME_SQL = Arel.sql("additional_attributes -> 'template_params' ->> 'name'").freeze

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    aggregate_totals(template_send_rows)
  end

  def timeseries
    aggregate_by_period(template_send_rows)
  end

  private

  def template_send_rows
    @template_send_rows ||= attach_responded(raw_template_sends)
  end

  def raw_template_sends
    scope = Message.where(account_id: account.id)
                    .where("additional_attributes -> 'template_params' ->> 'name' IS NOT NULL")
    scope = scope.where(created_at: range) if range.present?

    scope.order(:conversation_id, :created_at)
         .pluck(:id, :conversation_id, :created_at, :status, TEMPLATE_NAME_SQL)
         .map { |id, conversation_id, created_at, status, template_name| build_row(id, conversation_id, created_at, status, template_name) }
  end

  def build_row(id, conversation_id, created_at, status, template_name)
    { id: id, conversation_id: conversation_id, created_at: created_at, status: status, template_name: template_name }
  end

  # Un lead "contestó" a una plantilla si mandó un mensaje entrante después de recibirla, antes de
  # que le llegara la siguiente plantilla en esa misma conversación (para no atribuirle a una
  # plantilla vieja una respuesta que en realidad es reply a un envío posterior).
  def attach_responded(rows)
    boundaries = next_send_boundaries(rows)
    incoming_by_conversation = incoming_timestamps_by_conversation(rows)

    rows.each do |row|
      incoming_times = incoming_by_conversation[row[:conversation_id]] || []
      boundary = boundaries[row[:id]]
      row[:responded] = incoming_times.any? { |t| t > row[:created_at] && (boundary.nil? || t <= boundary) }
    end
  end

  def next_send_boundaries(rows)
    rows.group_by { |row| row[:conversation_id] }.each_with_object({}) do |(_conversation_id, conv_rows), boundaries|
      conv_rows.each_with_index do |row, index|
        boundaries[row[:id]] = conv_rows[index + 1]&.fetch(:created_at)
      end
    end
  end

  def incoming_timestamps_by_conversation(rows)
    return {} if rows.empty?

    conversation_ids = rows.map { |row| row[:conversation_id] }.uniq
    earliest_send = rows.map { |row| row[:created_at] }.min

    Message.where(conversation_id: conversation_ids, message_type: :incoming)
           .where('messages.created_at >= ?', earliest_send)
           .order(:created_at)
           .pluck(:conversation_id, :created_at)
           .group_by(&:first)
           .transform_values { |pairs| pairs.map(&:last) }
  end

  def aggregate_totals(rows)
    rows.group_by { |row| row[:template_name] }
        .map { |template_name, group| build_metrics(template_name, group) }
        .sort_by { |metric| -metric[:sent] }
  end

  def aggregate_by_period(rows)
    group_by = params[:group_by].presence || 'day'

    rows.group_by { |row| [period_key(row[:created_at], group_by), row[:template_name]] }
        .map { |(period, template_name), group| build_metrics(template_name, group).merge(period: period) }
        .sort_by { |metric| [metric[:period], metric[:template_name]] }
  end

  def period_key(time, group_by)
    case group_by
    when 'week' then time.beginning_of_week.to_date.to_s
    when 'month' then time.beginning_of_month.to_date.to_s
    when 'year' then time.beginning_of_year.to_date.to_s
    else time.to_date.to_s
    end
  end

  def build_metrics(template_name, rows)
    sent = rows.size
    responded = rows.count { |row| row[:responded] }

    {
      template_name: template_name,
      sent: sent,
      delivered: rows.count { |row| %w[delivered read].include?(row[:status]) },
      read: rows.count { |row| row[:status] == 'read' },
      failed: rows.count { |row| row[:status] == 'failed' },
      responded: responded,
      response_rate: safe_rate(responded, sent)
    }
  end

  def safe_rate(numerator, denominator)
    return 0.0 if denominator.to_i.zero?

    (numerator.to_f / denominator * 100).round(2)
  end
end
