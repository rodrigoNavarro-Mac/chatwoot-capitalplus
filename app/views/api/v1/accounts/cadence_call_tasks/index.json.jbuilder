json.array! @cadence_call_tasks do |task|
  json.partial! 'api/v1/models/cadence_call_task', formats: [:json], resource: task
end
