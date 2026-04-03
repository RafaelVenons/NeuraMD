class CanvasDocument < ApplicationRecord
  has_many :canvas_nodes, dependent: :destroy
  has_many :canvas_edges, dependent: :destroy

  validates :name, presence: true
  validate :viewport_shape

  scope :ordered, -> { order(:position, :name) }

  def viewport_x    = viewport&.dig("x") || 0
  def viewport_y    = viewport&.dig("y") || 0
  def viewport_zoom = viewport&.dig("zoom") || 1.0

  private

  def viewport_shape
    return if viewport.is_a?(Hash) && viewport.keys.all? { |k| %w[x y zoom].include?(k) }
    errors.add(:viewport, "must contain only x, y, zoom keys")
  end
end
