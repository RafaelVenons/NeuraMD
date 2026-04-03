FactoryBot.define do
  factory :note_view do
    sequence(:name) { |n| "View #{n}" }
    filter_query { "" }
    display_type { "table" }
    sort_config { {"field" => "updated_at", "direction" => "desc"} }
    columns { ["title", "updated_at"] }
    position { 0 }

    trait :with_filter do
      filter_query { "tag:neuro status:draft" }
    end

    trait :card do
      display_type { "card" }
    end

    trait :list do
      display_type { "list" }
    end
  end
end
