FactoryBot.define do
  factory :whatsapp_template_inbox_assignment do
    account
    inbox
    template_name { 'sample_template' }
  end
end
