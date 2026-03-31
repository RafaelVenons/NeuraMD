FactoryBot.define do
  factory :slug_redirect do
    note
    slug { Faker::Internet.slug }
  end
end
