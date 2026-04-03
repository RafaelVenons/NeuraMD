class CanvasEdge < ApplicationRecord
  EDGE_TYPES = %w[arrow line dashed].freeze

  belongs_to :canvas_document
  belongs_to :source_node, class_name: "CanvasNode"
  belongs_to :target_node, class_name: "CanvasNode"

  validates :edge_type, inclusion: {in: EDGE_TYPES}
  validates :source_node_id, uniqueness: {scope: :target_node_id}
end
