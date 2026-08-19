FactoryBot.define do
  factory :cadence_definition do
    account
    inbox
    name { Faker::Lorem.words(number: 3).join(' ') }
    active { true }
  end
end
