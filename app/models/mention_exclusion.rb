class MentionExclusion < ApplicationRecord
  belongs_to :note
  belongs_to :source_note, class_name: "Note"

  validates :matched_term, presence: true
  validates :source_note_id, uniqueness: {scope: [:note_id, :matched_term]}
end
