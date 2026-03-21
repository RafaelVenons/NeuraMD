FactoryBot.define do
  factory :ai_request do
    note_revision
    provider { "openai" }
    requested_provider { nil }
    capability { "grammar_review" }
    status { "queued" }
    sequence(:queue_position) { |n| n }
    attempts_count { 0 }
    max_attempts { 3 }
    next_retry_at { nil }
    last_error_at { nil }
    last_error_kind { nil }
    input_text { "Texto original." }
    output_text { nil }
    error_message { nil }
    metadata { {"language" => "pt-BR"} }
  end
end
