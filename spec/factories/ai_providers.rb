FactoryBot.define do
  factory :ai_provider do
    name { "openai" }
    enabled { true }
    base_url { nil }
    default_model_text { "gpt-4o-mini" }
    config { {} }
  end
end
