FactoryBot.define do
  factory :canvas_node do
    canvas_document
    node_type { "text" }
    x { 100.0 }
    y { 100.0 }
    width { 240.0 }
    height { 120.0 }
    data { {"text" => "Sample text"} }
    z_index { 0 }

    trait :note_type do
      node_type { "note" }
      note { association :note }
      data { {} }
    end

    trait :image_type do
      node_type { "image" }
      data { {"url" => "https://example.com/image.png"} }
    end

    trait :link_type do
      node_type { "link" }
      data { {"url" => "https://example.com"} }
    end

    trait :group_type do
      node_type { "group" }
      data { {"label" => "Group"} }
      width { 400.0 }
      height { 300.0 }
    end
  end
end
