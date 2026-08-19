FactoryBot.define do
  factory :cadence_call_task do
    account
    cadence_enrollment
    conversation
    step { 1 }
    status { 'pending' }
  end
end
