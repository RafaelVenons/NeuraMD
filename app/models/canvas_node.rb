class CanvasNode < ApplicationRecord
  NODE_TYPES = %w[note text image link group].freeze

  belongs_to :canvas_document
  belongs_to :note, optional: true

  has_many :outgoing_edges, class_name: "CanvasEdge", foreign_key: :source_node_id, dependent: :destroy
  has_many :incoming_edges, class_name: "CanvasEdge", foreign_key: :target_node_id, dependent: :destroy

  validates :node_type, inclusion: {in: NODE_TYPES}
  validates :note, presence: true, if: -> { node_type == "note" }
end
