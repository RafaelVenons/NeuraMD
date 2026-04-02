FactoryBot.define do
  factory :note_heading do
    note
    level { 2 }
    text { "Example Heading" }
    sequence(:slug) { |n| "example-heading-#{n}" }
    sequence(:position) { |n| n }
  end
end
