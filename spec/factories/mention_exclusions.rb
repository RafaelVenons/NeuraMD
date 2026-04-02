FactoryBot.define do
  factory :mention_exclusion do
    note
    source_note { association :note }
    matched_term { "some term" }
  end
end
