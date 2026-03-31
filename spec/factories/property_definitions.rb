FactoryBot.define do
  factory :property_definition do
    sequence(:key) { |n| "prop_#{n}" }
    value_type { "text" }
    config { {} }
    system { false }
    archived { false }
    position { 0 }

    trait :enum do
      value_type { "enum" }
      config { {"options" => %w[draft review published]} }
    end

    trait :multi_enum do
      value_type { "multi_enum" }
      config { {"options" => %w[tag_a tag_b tag_c]} }
    end

    trait :number do
      value_type { "number" }
    end

    trait :boolean do
      value_type { "boolean" }
    end

    trait :date do
      value_type { "date" }
    end

    trait :datetime do
      value_type { "datetime" }
    end

    trait :url do
      value_type { "url" }
    end

    trait :note_reference do
      value_type { "note_reference" }
    end

    trait :list do
      value_type { "list" }
    end

    trait :long_text do
      value_type { "long_text" }
    end

    trait :system do
      system { true }
    end

    trait :archived do
      archived { true }
    end
  end
end
