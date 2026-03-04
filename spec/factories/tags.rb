FactoryBot.define do
  factory :tag do
    name { Faker::Lorem.unique.word.downcase }
    color_hex { "##{Faker::Color.hex_color.delete("#")}" }
    tag_scope { "both" }
  end
end
