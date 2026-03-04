class NoteTag < ApplicationRecord
  self.primary_key = nil

  belongs_to :note
  belongs_to :tag
end
