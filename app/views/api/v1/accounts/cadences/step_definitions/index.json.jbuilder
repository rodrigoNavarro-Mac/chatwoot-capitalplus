json.array! @step_definitions do |step_definition|
  json.id step_definition.id
  json.position step_definition.position
  json.label step_definition.label
  json.template_key step_definition.template_key
  json.template_name step_definition.template_name
  json.template_language step_definition.template_language
  json.template_namespace step_definition.template_namespace
  json.schedule_type step_definition.schedule_type
  json.offset_minutes step_definition.offset_minutes
  json.day_offset step_definition.day_offset
  json.time_of_day step_definition.time_of_day
  json.wait_window_minutes step_definition.wait_window_minutes
  json.creates_call_task step_definition.creates_call_task
  json.active step_definition.active
  json.media_url step_definition.media_url
  json.media_type step_definition.media_type
  json.media_name step_definition.media_name
end
