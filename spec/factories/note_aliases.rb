FactoryBot.define do
  factory :note_alias do
    note
    name { Faker::Lorem.unique.words(number: 2).join(" ") }
  end
end
