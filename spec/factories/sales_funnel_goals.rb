FactoryBot.define do
  factory :sales_funnel_goal do
    account
    development_key { 'torre-1' }
    stage { 'lead_created' }
    period_month { Date.current.beginning_of_month }
    target_percent { 30 }
  end
end
