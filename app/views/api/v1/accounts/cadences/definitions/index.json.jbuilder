json.array! @cadence_definitions do |cadence_definition|
  json.id cadence_definition.id
  json.name cadence_definition.name
  json.segment_value cadence_definition.segment_value
  json.is_default cadence_definition.is_default
  json.active cadence_definition.active
  json.steps_count cadence_definition.cadence_step_definitions.count
  json.enrollments_count cadence_definition.cadence_enrollments.count
end
