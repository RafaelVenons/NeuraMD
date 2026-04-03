FactoryBot.define do
  factory :canvas_edge do
    canvas_document
    source_node { association :canvas_node, canvas_document: canvas_document }
    target_node { association :canvas_node, canvas_document: canvas_document }
    edge_type { "arrow" }
    label { nil }
    style { {} }
  end
end
