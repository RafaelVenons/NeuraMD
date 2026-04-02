class NoteHeading < ApplicationRecord
  belongs_to :note

  validates :level, presence: true, inclusion: {in: 1..6}
  validates :text, presence: true
  validates :slug, presence: true, uniqueness: {scope: :note_id}
  validates :position, presence: true, numericality: {greater_than_or_equal_to: 0, only_integer: true}
end
