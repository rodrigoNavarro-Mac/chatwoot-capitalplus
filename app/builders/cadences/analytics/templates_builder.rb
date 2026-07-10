class Cadences::Analytics::TemplatesBuilder < Cadences::Analytics::BaseBuilder
  def build
    Cadences::Analytics::StepsBuilder.new(account: account, filters: filters).build.map do |step_metrics|
      {
        template_key: step_metrics[:template_key],
        template_name: real_template_name(step_metrics[:template_key]),
        step: step_metrics[:step],
        sent: step_metrics[:sent],
        responded: step_metrics[:responded],
        response_rate: step_metrics[:response_rate],
        avg_response_time_seconds: step_metrics[:avg_response_time_seconds]
      }
    end
  end

  private

  def real_template_name(template_key)
    Cadences::TemplateResolver.mappings.dig('default', template_key, 'name')
  end
end
