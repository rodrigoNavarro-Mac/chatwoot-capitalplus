FactoryBot.define do
  factory :cadence_enrollment do
    account
    conversation
    inbox
    cadence_definition
    steps_snapshot { [{ position: 1, wait_hours: 0 }] }
  end
end
