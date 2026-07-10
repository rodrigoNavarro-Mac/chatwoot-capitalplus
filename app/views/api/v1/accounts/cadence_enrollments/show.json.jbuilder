json.partial! 'api/v1/models/cadence_enrollment', formats: [:json], resource: @cadence_enrollment
json.events do
  json.array! @cadence_enrollment.cadence_events.order(occurred_at: :asc) do |event|
    json.event_type event.event_type
    json.step event.step
    json.template_key event.template_key
    json.occurred_at event.occurred_at
    json.metadata event.metadata
  end
end
