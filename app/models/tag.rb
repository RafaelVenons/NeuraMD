class Tag < ApplicationRecord
  TAG_SCOPES = %w[note link both].freeze

  has_many :note_tags, dependent: :destroy
  has_many :notes, through: :note_tags
  has_many :link_tags, dependent: :destroy
  has_many :note_links, through: :link_tags

  validates :name, presence: true, uniqueness: {case_sensitive: false}
  validates :tag_scope, inclusion: {in: TAG_SCOPES}
  validates :color_hex, format: {with: /\A#[0-9A-Fa-f]{6}\z/}, allow_blank: true

  before_validation { self.name = name&.downcase&.strip }
end
