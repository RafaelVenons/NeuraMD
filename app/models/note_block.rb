class NoteBlock < ApplicationRecord
  BLOCK_TYPES = %w[paragraph list_item heading code blockquote table].freeze

  belongs_to :note

  validates :block_id, presence: true, uniqueness: {scope: :note_id},
    format: {with: /\A[a-zA-Z0-9-]+\z/}
  validates :content, presence: true
  validates :block_type, presence: true, inclusion: {in: BLOCK_TYPES}
  validates :position, presence: true, numericality: {greater_than_or_equal_to: 0, only_integer: true}
end
