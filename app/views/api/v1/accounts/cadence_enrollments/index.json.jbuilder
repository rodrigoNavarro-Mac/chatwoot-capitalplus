json.array! @cadence_enrollments do |enrollment|
  json.partial! 'api/v1/models/cadence_enrollment', formats: [:json], resource: enrollment
end
