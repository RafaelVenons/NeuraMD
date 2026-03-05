FactoryBot.define do
  factory :note_revision do
    note
    author { nil }
    content_markdown { "# #{Faker::Lorem.sentence}\n\n#{Faker::Lorem.paragraphs(number: 2).join("\n\n")}" }
    change_summary { Faker::Lorem.sentence }
    revision_kind { :checkpoint }
    ai_generated { false }
  end
end
