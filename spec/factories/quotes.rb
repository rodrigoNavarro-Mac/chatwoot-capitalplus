FactoryBot.define do
  factory :quote do
    account
    source_type { 'product' }
    trigger_source { 'chatwoot_ui' }
    status { 'completed' }
    sequence(:zoho_product_id) { |n| "product-#{n}" }

    trait :failed do
      status { 'failed' }
    end
  end
end
