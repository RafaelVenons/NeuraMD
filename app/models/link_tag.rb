class LinkTag < ApplicationRecord
  self.primary_key = nil

  belongs_to :note_link
  belongs_to :tag
end
