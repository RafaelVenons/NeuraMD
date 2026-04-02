FactoryBot.define do
  factory :note_block do
    note
    sequence(:block_id) { |n| "block-#{n}" }
    content { "Example block content" }
    block_type { "paragraph" }
    sequence(:position) { |n| n }
  end
end
